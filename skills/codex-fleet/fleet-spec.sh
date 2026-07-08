#!/usr/bin/env bash
set -euo pipefail

G="${CODEX_GOALS_DIR:-$HOME/.codex-goals}"

usage() {
  cat >&2 <<'USAGE'
usage:
  fleet-spec.sh init <name> <path> <tier> <verify_cmd> <push_allowed> <danger> <default_branch>
  fleet-spec.sh get <name> <jq-path>
  fleet-spec.sh set <name> <jq-assignment>
  fleet-spec.sh render <name>
USAGE
  exit 2
}

need_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "ERR: jq not found in PATH" >&2
    exit 1
  fi
}

spec_file() {
  printf '%s/%s.spec.json\n' "$G" "$1"
}

json_quote() {
  # Emit a YAML/JSON-safe double-quoted scalar. --arg already makes $v a JSON
  # string; do NOT pipe through @json or it double-encodes ("\"npm test\"").
  jq -n --arg v "$1" '$v'
}

normalize_bool() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    true|1|yes) printf 'true\n' ;;
    *) printf 'false\n' ;;
  esac
}

require_spec() {
  local f
  f="$(spec_file "$1")"
  if [ ! -f "$f" ]; then
    echo "ERR: spec mirror not found: $f" >&2
    exit 1
  fi
  printf '%s\n' "$f"
}

spec_init() {
  [ "$#" -eq 7 ] || usage
  local name="$1" path="$2" tier="$3" verify_cmd="$4" push_allowed="$5" danger="$6" default_branch="$7"
  local f push_bool

  mkdir -p "$G"
  f="$(spec_file "$name")"
  if [ -f "$f" ]; then
    echo "kept existing spec mirror: $f"
    return 0
  fi

  case "$tier" in
    prototype|production) ;;
    *) echo "ERR: tier must be prototype or production (got '$tier')" >&2; exit 1 ;;
  esac

  push_bool="$(normalize_bool "$push_allowed")"
  jq -n \
    --arg project "$name" \
    --arg path "$path" \
    --arg tier "$tier" \
    --arg verify_cmd "$verify_cmd" \
    --argjson push_allowed "$push_bool" \
    --arg danger "$danger" \
    --arg default_branch "$default_branch" \
    '{
      project: $project,
      path: $path,
      tier: $tier,
      status: "planned",
      current_round: 1,
      verify_cmd: $verify_cmd,
      push_allowed: $push_allowed,
      danger: $danger,
      default_branch: $default_branch,
      approved_story: null,
      branch_lineage: [],
      pending_question: null
    }' > "$f"
  echo "wrote spec mirror: $f"
}

spec_get() {
  [ "$#" -ge 2 ] || usage
  local f expr
  f="$(require_spec "$1")"
  shift
  expr="$*"
  jq -r "$expr" "$f"
}

spec_set() {
  [ "$#" -ge 2 ] || usage
  local name="$1" f expr tmp
  f="$(require_spec "$name")"
  shift
  expr="$*"
  tmp="$(mktemp "$G/$name.spec.json.XXXXXX")"
  if jq "$expr" "$f" > "$tmp"; then
    mv "$tmp" "$f"
  else
    rm -f "$tmp"
    exit 1
  fi
}

extract_block() {
  local file="$1" header="$2"
  [ -f "$file" ] || return 1
  awk -v header="$header" '
    $0 == header { found = 1; print; next }
    found && /^## / { exit }
    found { print }
    END { if (!found) exit 1 }
  ' "$file"
}

write_block() {
  local file="$1" header="$2" scaffold="$3" block
  if block="$(extract_block "$file" "$header")"; then
    printf '%s\n\n' "$block"
  else
    printf '%s\n\n%s\n\n' "$header" "$scaffold"
  fi
}

render_lineage_yaml() {
  local f="$1"
  jq -r '
    if ((.branch_lineage // []) | length) == 0 then
      "  []"
    else
      (.branch_lineage // [])[] |
      "  - round: \(.round // "")\n" +
      "    branch: \((.branch // "") | @json)\n" +
      "    base: \((.base // "") | @json)\n" +
      "    pr: \((.pr // "") | @json)\n" +
      "    commit: \((.commit // "") | @json)\n" +
      "    status: \((.status // "") | @json)\n" +
      "    note: \((.note // "") | @json)"
    end
  ' "$f"
}

render_acceptance() {
  local f="$1"
  jq -r '
    (.approved_story.acceptanceCriteria // [])[]? | "- " + tostring
  ' "$f"
}

render_rounds() {
  local f="$1"
  jq -r '
    def story_lines:
      if .approved_story == null then empty else
        "### Round \(.current_round) — \(.approved_story.title // "approved story")\n" +
        "why: \(.approved_story.why // "")\n" +
        "acceptance:\n" +
        (((.approved_story.acceptanceCriteria // []) | map("- " + tostring) | join("\n")) // "") + "\n" +
        "key files: " + (((.approved_story.keyFiles // []) | join(", ")) // "") + "\n"
      end;
    ((.branch_lineage // [])[]? |
      "### Round \(.round) — \(.branch // "slice")\n" +
      "base: \(.base // "")\n" +
      "branch: \(.branch // "")\n" +
      "pr: \(.pr // "")\n" +
      "commit: \(.commit // "")\n" +
      "status: \(.status // "")\n" +
      "note: \(.note // "")\n"
    ),
    story_lines
  ' "$f"
}

spec_render() {
  [ "$#" -eq 1 ] || usage
  local name="$1" f repo out tmp project tier status round verify_cmd push_allowed danger

  f="$(require_spec "$name")"
  repo="$(jq -r '.path' "$f")"
  if [ -z "$repo" ] || [ "$repo" = "null" ]; then
    echo "ERR: spec mirror missing path for $name" >&2
    exit 1
  fi

  project="$(jq -r '.project' "$f")"
  tier="$(jq -r '.tier' "$f")"
  status="$(jq -r '.status' "$f")"
  round="$(jq -r '.current_round' "$f")"
  verify_cmd="$(jq -r '.verify_cmd' "$f")"
  push_allowed="$(jq -r '.push_allowed' "$f")"
  danger="$(jq -r '.danger' "$f")"

  mkdir -p "$repo/docs/fleet"
  out="$repo/docs/fleet/spec.md"
  tmp="$(mktemp "$repo/docs/fleet/spec.md.XXXXXX")"

  {
    printf '%s\n' '---'
    printf 'project: %s\n' "$project"
    printf 'tier: %s\n' "$tier"
    printf 'status: %s\n' "$status"
    printf 'current_round: %s\n' "$round"
    printf 'verify_cmd: %s\n' "$(json_quote "$verify_cmd")"
    printf 'push_allowed: %s\n' "$push_allowed"
    printf 'danger: %s\n' "$(json_quote "$danger")"
    printf '%s\n' 'branch_lineage:'
    render_lineage_yaml "$f"
    printf '%s\n\n' '---'
    printf '# %s — fleet spec\n\n' "$project"
    write_block "$out" '## Intent' '<running scope conversation>'
    printf '## Stakes\n\n%s\n\n' "$tier"
    printf '## Acceptance bar\n\n'
    printf -- '- verify: `%s` green\n' "$verify_cmd"
    render_acceptance "$f"
    printf '\n'
    write_block "$out" '## Decided' ''
    write_block "$out" '## Deferred' ''
    printf '## Rounds\n\n'
    render_rounds "$f"
  } > "$tmp"

  mv "$tmp" "$out"
  echo "rendered spec: $out"
}

main() {
  need_jq
  [ "$#" -ge 1 ] || usage
  local cmd="$1"
  shift
  case "$cmd" in
    init) spec_init "$@" ;;
    get) spec_get "$@" ;;
    set) spec_set "$@" ;;
    render) spec_render "$@" ;;
    *) usage ;;
  esac
}

main "$@"
