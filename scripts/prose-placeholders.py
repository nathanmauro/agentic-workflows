#!/usr/bin/env python3
"""Report unresolved placeholders in Markdown prose.

Fenced code blocks and inline code are skipped: an angle-bracket placeholder such as <repo> is
legitimate inside a command example. The exit code mirrors ripgrep so the audit can treat the
two the same way: 0 when at least one match was printed, 1 when nothing matched, and 2 on an
error such as a missing root or a file that is not valid UTF-8.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

EXIT_MATCH = 0
EXIT_NO_MATCH = 1
EXIT_ERROR = 2

ALLOWED_TAGS = ("p", "h1", "strong", "br", "a", "img", "sub")
PLACEHOLDER = re.compile(
    r"TBD|TODO|FIXME|<(?!/?(?:" + "|".join(ALLOWED_TAGS) + r")(?:\s|/?>))[^>]+>"
)
FENCE = re.compile(r"^\s*(```|~~~)")
INLINE_CODE = re.compile(r"`[^`]*`")


class ScanError(Exception):
    pass


def markdown_files(roots: list[str]) -> list[Path]:
    files: list[Path] = []
    for root in roots:
        path = Path(root)
        if path.is_file():
            files.append(path)
        elif path.is_dir():
            files.extend(sorted(path.rglob("*.md")))
        else:
            # A renamed or missing root must not read as a clean scan.
            raise ScanError(f"no such file or directory: {root}")
    return files


def prose_lines(path: Path):
    in_fence = False
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if FENCE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        yield number, INLINE_CODE.sub("", line)


def main(argv: list[str]) -> int:
    matched = False
    try:
        for path in markdown_files(argv[1:]):
            try:
                for number, text in prose_lines(path):
                    if PLACEHOLDER.search(text):
                        matched = True
                        print(f"./{path}:{number}:{text}")
            except (OSError, UnicodeDecodeError) as exc:
                raise ScanError(f"{path}: {exc}") from exc
    except ScanError as exc:
        print(f"prose-placeholders: {exc}", file=sys.stderr)
        return EXIT_ERROR
    return EXIT_MATCH if matched else EXIT_NO_MATCH


if __name__ == "__main__":
    sys.exit(main(sys.argv))
