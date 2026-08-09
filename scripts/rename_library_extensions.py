#!/usr/bin/env python3
"""Rename a library of TopPresenter `.json` files to their v1 extensions.

    python3 scripts/rename_library_extensions.py ExtraAssets            # dry run
    python3 scripts/rename_library_extensions.py ExtraAssets --apply

Since v1 the native formats own their extensions (`.tpbible`, `.tpsong`,
`.tpsongcollection`, `.tpslides`), and the app no longer reads `.json` at all —
it refuses one with a message telling you to rename it. This is that rename.
The bytes do not change.

It decides by the file's OWN `format` marker, not by which folder it is in.
A folder is a guess; the marker is the file saying what it is. Anything without
a TopPresenter marker — a `_manifest.json`, a `_completeness.json`, somebody's
unrelated JSON — is left alone and counted, so a stray file cannot be renamed
into a format it is not.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
from collections import Counter

# The marker each format writes into its header.
MARKER_TO_EXTENSION = {
    "TopPresenter Bible": "tpbible",
    "TopPresenter Song": "tpsong",
    "TopPresenter Songs": "tpsongcollection",
    "TopPresenter Slides": "tpslides",
    "TopPresenter Session": "tpschedule",
}

# Enough to reach the header without reading a 30 MB Bible into memory.
PROBE_BYTES = 4096
MARKER_PATTERN = re.compile(rb'"format"\s*:\s*"([^"]+)"')


def marker_of(path: pathlib.Path) -> str | None:
    """The file's declared format, or None when it does not declare one."""
    try:
        with path.open("rb") as handle:
            head = handle.read(PROBE_BYTES)
    except OSError:
        return None
    match = MARKER_PATTERN.search(head)
    if match:
        return match.group(1).decode("utf-8", "replace")
    # A pretty-printed file can push `format` past the probe on a big header.
    # Rare, so pay the full parse only when the cheap read found nothing.
    if len(head) == PROBE_BYTES:
        try:
            return json.loads(path.read_bytes()).get("format")
        except (OSError, ValueError, AttributeError):
            return None
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("root", type=pathlib.Path)
    parser.add_argument("--apply", action="store_true",
                        help="actually rename; without it, nothing is touched")
    args = parser.parse_args()

    if not args.root.is_dir():
        print(f"not a directory: {args.root}", file=sys.stderr)
        return 1

    planned: list[tuple[pathlib.Path, pathlib.Path]] = []
    counts: Counter[str] = Counter()

    for path in sorted(args.root.rglob("*.json")):
        marker = marker_of(path)
        extension = MARKER_TO_EXTENSION.get(marker or "")
        if extension is None:
            counts[f"left alone ({marker or 'no TopPresenter marker'})"] += 1
            continue
        target = path.with_suffix("." + extension)
        if target.exists():
            counts["skipped — target already exists"] += 1
            continue
        planned.append((path, target))
        counts[f"{marker} -> .{extension}"] += 1

    for label, count in sorted(counts.items()):
        print(f"{count:>7}  {label}")

    if not args.apply:
        print(f"\nDry run. {len(planned)} files would be renamed; pass --apply to do it.")
        return 0

    for source, target in planned:
        source.rename(target)
    print(f"\nRenamed {len(planned)} files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
