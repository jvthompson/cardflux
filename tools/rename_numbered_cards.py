#!/usr/bin/env python3
"""Rename numbered-slug card titles in a gamedef.json file.

Finds any "cardTitle" field whose value looks like a numbered slug,
e.g. "076-genie-powers-unleashed", and rewrites it to a clean
title-cased name, e.g. "Genie Powers Unleashed" (leading number and
punctuation stripped, each word capitalized).

Works on any gamedef.json regardless of how deeply the cards are
nested (list of cards, dict keyed by card id, etc.) -- it recursively
walks the whole JSON tree and only touches keys literally named
"cardTitle" (case-insensitive) so card ids/other slug-like fields are
left alone.

Usage:
    python rename_numbered_cards.py <path-to-gamedef.json>
    python rename_numbered_cards.py <path-to-gamedef.json> --in-place
    python rename_numbered_cards.py <path-to-gamedef.json> --dry-run
    python rename_numbered_cards.py <path-to-gamedef.json> -o <output-path>

By default (no flags) it leaves the original file untouched and writes
a copy named "<stem>_renamed.json" next to it.
"""

import argparse
import json
import re
import shutil
import sys
from pathlib import Path

NUMBERED_SLUG_RE = re.compile(r"^\d+-[a-z0-9]+(?:-[a-z0-9]+)*$", re.IGNORECASE)


def slug_to_title(value: str) -> str:
    """Turn '076-genie-powers-unleashed' into 'Genie Powers Unleashed'."""
    without_number = re.sub(r"^\d+-", "", value)
    words = [w for w in re.split(r"[-_]+", without_number) if w]
    return " ".join(word.capitalize() for word in words)


def rename_numbered_cards(obj, changes):
    """Recursively walk obj, renaming any 'cardTitle' field matching the slug pattern."""
    if isinstance(obj, dict):
        for key, value in obj.items():
            if isinstance(value, str) and key.lower() == "cardtitle" and NUMBERED_SLUG_RE.match(value):
                new_value = slug_to_title(value)
                changes.append((value, new_value))
                obj[key] = new_value
            else:
                rename_numbered_cards(value, changes)
    elif isinstance(obj, list):
        for item in obj:
            rename_numbered_cards(item, changes)


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("gamedef", type=Path, help="Path to gamedef.json")
    parser.add_argument(
        "--in-place",
        action="store_true",
        help="Edit the file in place (writes a .bak backup first)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Only print what would change; write nothing",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=None,
        help="Explicit output path (ignored with --in-place or --dry-run)",
    )
    args = parser.parse_args()

    if not args.gamedef.is_file():
        sys.exit(f"File not found: {args.gamedef}")

    with args.gamedef.open("r", encoding="utf-8") as f:
        data = json.load(f)

    changes = []
    rename_numbered_cards(data, changes)

    if not changes:
        print("No cardTitle fields matched the numbered-slug pattern; nothing to do.")
        return

    print(f"Renamed {len(changes)} card title(s):")
    for old, new in changes:
        print(f"  {old!r} -> {new!r}")

    if args.dry_run:
        print("\nDry run: no files were written.")
        return

    if args.in_place:
        backup_path = args.gamedef.with_suffix(args.gamedef.suffix + ".bak")
        shutil.copy2(args.gamedef, backup_path)
        out_path = args.gamedef
        print(f"\nBackup written to {backup_path}")
    else:
        out_path = args.output or args.gamedef.with_name(
            f"{args.gamedef.stem}_renamed{args.gamedef.suffix}"
        )

    with out_path.open("w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"Wrote updated file to {out_path}")


if __name__ == "__main__":
    main()
