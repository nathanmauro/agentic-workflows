#!/usr/bin/env bash
# fleet-prompt.sh
# Build native Claude Code AskUserQuestion payloads for the codex-fleet loop.
#
# This is the data layer behind the native interaction surface: the loop runs
# this helper, then calls the AskUserQuestion tool with each emitted batch
# verbatim, so the human owner sees option-style prompts on mobile / CLU (with a freeform
# "Other" choice for redirect / discussion) instead of typing command grammar.
#
# usage:
#   fleet-prompt.sh approval <round>   # one question per project awaiting approval
#   fleet-prompt.sh clarify            # one question per open/notified Codex question
#
# Output (stdout): {"batches": [[q, q, q, q], [q, ...]]}
#   - Each batch holds <= 4 question objects (AskUserQuestion caps questions at 4).
#   - Each question object is shaped for AskUserQuestion.questions[]:
#       {header, question, multiSelect, options:[{label, description}, ...]}
#   - "Other" (freeform) is added by AskUserQuestion automatically; the question
#     text tells the human owner they can pick it to redirect / discuss / answer in words.
#
# The loop interprets answers and performs the SAME mirror writes as before
# (approve -> approved_story+doing; skip -> skipped; redirect text -> approved_story;
# clarification answer -> <name>.answer.txt + relaunch). This helper only builds
# the prompt payload; it never mutates fleet state.

set -euo pipefail

G="${CODEX_GOALS_DIR:-$HOME/.codex-goals}"

usage() {
  cat >&2 <<'USAGE'
usage:
  fleet-prompt.sh approval <round>
  fleet-prompt.sh clarify
USAGE
  exit 2
}

need_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "ERR: jq not found in PATH" >&2
    exit 1
  fi
}

# Pack a flat questions array into AskUserQuestion batches of <= 4.
batch() {
  jq -c '{batches: [ range(0; length; 4) as $i | .[$i:$i+4] ]}'
}

prompt_approval() {
  [ "$#" -eq 1 ] || usage
  local round="$1"
  local recon="$G/recon-round-$round.json"
  if [ ! -f "$recon" ]; then
    echo "ERR: no recon file: $recon" >&2
    exit 1
  fi

  local questions='[]'
  local n i obj project spec tier verify status flipped header q
  n="$(jq 'length' "$recon")"
  i=0
  while [ "$i" -lt "$n" ]; do
    obj="$(jq -c ".[$i]" "$recon")"
    i=$((i + 1))
    project="$(printf '%s' "$obj" | jq -r '.project // ""')"
    [ -n "$project" ] && [ "$project" != "null" ] || continue

    spec="$G/$project.spec.json"
    if [ -f "$spec" ]; then
      tier="$(jq -r '.tier // "production"' "$spec")"
      verify="$(jq -r '.verify_cmd // ""' "$spec")"
      status="$(jq -r '.status // "planned"' "$spec")"
    else
      tier="$(printf '%s' "$obj" | jq -r '.tier // "production"')"
      verify=""
      status="planned"
    fi

    # APPROVAL only proposes projects still awaiting a decision.
    case "$status" in
      planned) ;;
      *) continue ;;
    esac

    if [ "$tier" = "prototype" ]; then flipped="production"; else flipped="prototype"; fi
    header="$(printf '%s' "$project" | cut -c1-12)"

    q="$(jq -n \
      --arg project "$project" \
      --arg header "$header" \
      --arg round "$round" \
      --arg tier "$tier" \
      --arg flipped "$flipped" \
      --arg verify "$verify" \
      --argjson obj "$obj" '
      (($obj.nextTask.title // $obj.sliceSummary // "next slice")) as $title |
      (($obj.nextTask.why // "") | .[0:200]) as $why |
      (($obj.sliceSummary // "") | .[0:140]) as $slice |
      ((($obj.nextTask.acceptanceCriteria // [])[0:3]) | map(tostring) | join("; ")) as $acc |
      {
        header: $header,
        question: (
          "Round " + $round + " — " + $project + ": recon proposes \"" + $title + "\". "
          + (if $why  != "" then $why + " " else "" end)
          + (if $slice != "" then "Slice: " + $slice + ". " else "" end)
          + "Tier " + $tier
          + (if $verify != "" then "; verify: " + $verify else "" end) + ". "
          + (if $acc != "" then "Acceptance: " + $acc + ". " else "" end)
          + "Approve, Skip, or choose Other to redirect (type a new direction) or discuss."
        ),
        multiSelect: false,
        options: [
          { label: "Approve (Recommended)", description: ("Run this slice as proposed at " + $tier + " tier.") },
          { label: "Skip", description: ("Skip " + $project + " this round; no slice runs.") },
          { label: ("Approve as " + $flipped), description: ("Switch " + $project + " to " + $flipped + " tier, then run the slice.") }
        ]
      }')"
    questions="$(jq -c --argjson q "$q" '. + [$q]' <<<"$questions")"
  done

  printf '%s' "$questions" | batch
}

prompt_clarify() {
  [ "$#" -eq 0 ] || usage
  local questions='[]'
  local qf st project header q

  shopt -s nullglob
  for qf in "$G"/*.question.json; do
    st="$(jq -r '.status // "open"' "$qf" 2>/dev/null || echo "")"
    case "$st" in
      open|notified) ;;
      *) continue ;;
    esac
    project="$(basename "$qf" .question.json)"
    header="$(printf '%s' "$project" | cut -c1-12)"

    q="$(jq -n \
      --arg project "$project" \
      --arg header "$header" \
      --slurpfile qq "$qf" '
      ($qq[0]) as $d |
      ([ ($d.options // [])[] | tostring ][0:4]) as $picked |
      ($picked | map({ label: (.[0:60]), description: . })) as $mapped |
      ($mapped + [
        { label: "Proceed with the sensible default", description: "Let Codex pick the most reasonable option and continue." },
        { label: "Other approach", description: "None of these fit — choose Other to type your own answer." }
      ]) as $padded |
      ($padded[0: (if ($mapped|length) >= 2 then ($mapped|length) else 2 end)]) as $finalopts |
      {
        header: $header,
        question: (
          "[" + $project + "] " + ($d.question // "Codex hit a fork and needs a decision.")
          + (if (($d.context // "") | length) > 0 then "  Context: " + ($d.context | tostring) else "" end)
          + "  Pick an option, or choose Other to answer / discuss in your own words."
        ),
        multiSelect: false,
        options: $finalopts
      }')"
    questions="$(jq -c --argjson q "$q" '. + [$q]' <<<"$questions")"
  done

  printf '%s' "$questions" | batch
}

main() {
  need_jq
  [ "$#" -ge 1 ] || usage
  local cmd="$1"
  shift
  case "$cmd" in
    approval) prompt_approval "$@" ;;
    clarify)  prompt_clarify "$@" ;;
    *) usage ;;
  esac
}

main "$@"
