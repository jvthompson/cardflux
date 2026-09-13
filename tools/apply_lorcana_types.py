#!/usr/bin/env python3
"""Backfill CardDefinition.types in a Lorcana gamedef.json from allCards.json.

allCards.json is the lorcanajson.org card database (https://lorcanajson.org).
For every card in gamedef.json, this looks up the matching entry in
allCards.json by name (gamedef's "cardTitle" vs allCards' "simpleName",
matched case-insensitively after normalization) and adds any of the
following tags to that card's "types" list if not already present:

  - its card Type (Character / Action / Item / Location)
  - its ink Color(s) (dual-ink cards like "Amber-Ruby" become two
    separate tags: "Amber" and "Ruby")
  - each of its Subtypes (e.g. "Storyborn", "Hero", "Princess")
  - "Inkable" if the card's "inkwell" field is true
  - "Singer" if "Singer" appears in the card's "keywordAbilities"

Existing types are never removed or reordered; only missing tags are
appended. Cards whose name can't be matched are left untouched and
listed in the summary so they can be reconciled by hand.

Usage:
    python apply_lorcana_types.py <allCards.json> <gamedef.json>
    python apply_lorcana_types.py <allCards.json> <gamedef.json> --in-place
    python apply_lorcana_types.py <allCards.json> <gamedef.json> --dry-run
    python apply_lorcana_types.py <allCards.json> <gamedef.json> -o <output-path>

By default (no flags) the original gamedef.json is left untouched and a
copy named "<stem>_with_types.json" is written next to it.
"""

import argparse
import json
import re
import shutil
import sys
import unicodedata
from pathlib import Path


def normalize(value: str) -> str:
    """Lowercase, strip diacritics, and collapse punctuation/whitespace to single spaces."""
    decomposed = unicodedata.normalize("NFKD", value)
    ascii_only = "".join(ch for ch in decomposed if not unicodedata.combining(ch))
    lowered = ascii_only.lower()
    collapsed = re.sub(r"[^a-z0-9]+", " ", lowered)
    return collapsed.strip()


def build_tag_index(all_cards_path: Path):
    """Return {normalized simpleName: [tags...]}, tags unioned across same-name reprints."""
    with all_cards_path.open("r", encoding="utf-8") as f:
        data = json.load(f)

    index = {}
    for card in data["cards"]:
        key = normalize(card["simpleName"])
        tags = index.setdefault(key, [])

        def add_tag(tag):
            if tag and tag not in tags:
                tags.append(tag)

        add_tag(card.get("type"))
        for color in (card.get("color") or "").split("-"):
            add_tag(color)
        subtypes = card.get("subtypes")
        if isinstance(subtypes, list):
            for subtype in subtypes:
                add_tag(subtype)
        if card.get("inkwell") is True:
            add_tag("Inkable")
        keyword_abilities = card.get("keywordAbilities") or []
        if any(keyword == "Singer" for keyword in keyword_abilities):
            add_tag("Singer")

    return index


def iter_gamedef_cards(gamedef):
    for game_set in gamedef.get("sets", []):
        for card in game_set.get("cards", []):
            yield card


def apply_types(gamedef, tag_index):
    updated = []
    unchanged = []
    unmatched = []

    for card in iter_gamedef_cards(gamedef):
        title = card.get("cardTitle", "")
        key = normalize(title)
        tags = tag_index.get(key)
        if tags is None:
            unmatched.append(title)
            continue

        existing = card.setdefault("types", [])
        existing_lower = {t.lower() for t in existing}
        added = [t for t in tags if t.lower() not in existing_lower]
        if added:
            existing.extend(added)
            updated.append((title, added))
        else:
            unchanged.append(title)

    return updated, unchanged, unmatched


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "all_cards", type=Path, help="Path to allCards.json (lorcanajson.org format)"
    )
    parser.add_argument("gamedef", type=Path, help="Path to gamedef.json")
    parser.add_argument(
        "--in-place",
        action="store_true",
        help="Edit gamedef.json in place (writes a .bak backup first)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Only print the summary; write nothing",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=None,
        help="Explicit output path (ignored with --in-place or --dry-run)",
    )
    args = parser.parse_args()

    if not args.all_cards.is_file():
        sys.exit(f"File not found: {args.all_cards}")
    if not args.gamedef.is_file():
        sys.exit(f"File not found: {args.gamedef}")

    tag_index = build_tag_index(args.all_cards)

    with args.gamedef.open("r", encoding="utf-8") as f:
        gamedef = json.load(f)

    updated, unchanged, unmatched = apply_types(gamedef, tag_index)

    total = len(updated) + len(unchanged) + len(unmatched)
    print(f"{total} card(s) in gamedef.json")
    print(f"  {len(updated)} updated with new type tag(s)")
    print(f"  {len(unchanged)} already up to date")
    print(f"  {len(unmatched)} could not be matched by name")

    if unmatched:
        print("\nUnmatched card titles (left untouched):")
        for title in unmatched:
            print(f"  - {title}")

    if args.dry_run:
        print("\nDry run: no files were written.")
        return

    if not updated:
        print("\nNo changes to write.")
        return

    if args.in_place:
        backup_path = args.gamedef.with_suffix(args.gamedef.suffix + ".bak")
        shutil.copy2(args.gamedef, backup_path)
        out_path = args.gamedef
        print(f"\nBackup written to {backup_path}")
    else:
        out_path = args.output or args.gamedef.with_name(
            f"{args.gamedef.stem}_with_types{args.gamedef.suffix}"
        )

    with out_path.open("w", encoding="utf-8") as f:
        json.dump(gamedef, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"Wrote updated file to {out_path}")


if __name__ == "__main__":
    main()
