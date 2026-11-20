#!/usr/bin/env python3
"""Print the facts CODE_MAP.md quotes, so the document never has to be trusted about numbers.

The doc used to carry hand-written file counts and "about 1900 lines" claims, and every refactor
left a few of them lying. This prints the numbers; `--check` compares them against what the doc
currently says and fails when they disagree.

    tools/doc_facts.py            # print the facts
    tools/doc_facts.py --check    # exit 1 if CODE_MAP.md is out of date
    tools/doc_facts.py --update   # rewrite the numbers CODE_MAP.md states
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIB = ROOT / "lib"
MAP = ROOT / "CODE_MAP.md"

# Files that deserve a line in "体量较大的文件" (section 8). Anything longer than this is listed,
# longest first, so the list cannot quietly go stale.
BIG_FILE_LINES = 700

# A markdown table row in section 3 that describes a source file: `| `name.dart` | ...`.
FILE_ROW = re.compile(r"^\|\s*`([a-z0-9_]+\.dart)`")


@dataclass(frozen=True)
class Fact:
    label: str
    value: int


def dart_files(root: Path) -> list[Path]:
    return sorted(p for p in root.rglob("*.dart") if "build" not in p.parts)


def line_count(path: Path) -> int:
    return len(path.read_text(encoding="utf-8").splitlines())


def facts() -> list[Fact]:
    files = dart_files(LIB)
    return [
        Fact("lib_files", len(files)),
    ]


def big_files() -> list[tuple[str, int]]:
    rows = [(str(p.relative_to(ROOT)), line_count(p)) for p in dart_files(LIB)]
    rows = [row for row in rows if row[1] >= BIG_FILE_LINES]
    return sorted(rows, key=lambda row: -row[1])


def described_files() -> set[str]:
    """Every file the map names, and every directory it gives a section-3 row to.

    Section 3.2–3.5 name individual files; section 3.6–3.7 name a *directory* (`| `detail/` | …`)
    and describe what lives in it. Both count as covered, so a file is only reported when neither
    its name nor its folder appears.
    """
    text = MAP.read_text(encoding="utf-8")
    names: set[str] = set()
    for line in text.splitlines():
        match = FILE_ROW.match(line)
        if match:
            names.add(match.group(1))
    folders = set(re.findall(r"^\|\s*`([a-z0-9_]+)/`", text, re.MULTILINE))
    return names | folders


def missing_from_map() -> list[tuple[str, str]]:
    """Files that exist but neither the file nor its folder is described in section 3.

    Returns `(reason, path)` so the report can say which of the two was missing.
    """
    described = described_files()
    out: list[tuple[str, str]] = []
    for path in dart_files(LIB):
        rel = path.relative_to(LIB)
        if path.name in described:
            continue
        if rel.parts[0] == "features" and len(rel.parts) > 2 and rel.parts[1] in described:
            continue
        # `core/` files are named one by one, so a core file with no row is genuinely unlisted.
        reason = "no row and no folder" if rel.parts[0] == "features" else "no row"
        out.append((reason, str(path.relative_to(ROOT))))
    return out


def stated(name: str) -> int | None:
    """The number the document states for [name], or None when it states none.

    The doc phrases these in Chinese around the number (`共 125 个 Dart 文件`), so each field is
    matched by its own pattern rather than by a shared `name: value` shape. A field with no pattern
    is one the doc no longer states — which is the point of this script.
    """
    patterns = {
        "lib_files": r"共\s*(\d+)\s*个 Dart 文件",
    }
    pattern = patterns.get(name)
    if pattern is None:
        return None
    match = re.search(pattern, MAP.read_text(encoding="utf-8"))
    return int(match.group(1)) if match else None


def main(argv: list[str]) -> int:
    if "--update" in argv:
        text = MAP.read_text(encoding="utf-8")
        for fact in facts():
            text = re.sub(
                r"共\s*\d+\s*个 Dart 文件",
                f"共 {fact.value} 个 Dart 文件",
                text,
            )
        MAP.write_text(text, encoding="utf-8")
        print(f"updated {MAP.relative_to(ROOT)}")
        return 0

    current = facts()

    if "--check" in argv:
        problems = []
        for fact in current:
            say = stated(fact.label)
            if say is not None and say != fact.value:
                problems.append(f"{fact.label}: doc says {say}, actual {fact.value}")
        missing = missing_from_map()
        if missing:
            shown = ", ".join(path for _, path in missing[:8])
            problems.append(f"{len(missing)} file(s) not in section 3: {shown}" + (" …" if len(missing) > 8 else ""))
        if problems:
            print("\n".join(problems))
            return 1
        print("CODE_MAP.md agrees with the code")
        return 0

    for fact in current:
        print(f"{fact.label}: {fact.value}")
    print()
    print(f"files >= {BIG_FILE_LINES} lines:")
    for path, lines in big_files():
        print(f"  {lines:6d}  {path}")
    missing = missing_from_map()
    if missing:
        print()
        print(f"not described in section 3 ({len(missing)}):")
        for reason, path in missing:
            print(f"  {path}  ({reason})")
    else:
        print()
        print("every file is described in section 3")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
