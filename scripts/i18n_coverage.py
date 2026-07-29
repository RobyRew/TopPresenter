#!/usr/bin/env python3
"""Translation coverage for TopPresenter's String Catalog.

Reads TopPresenter/Localizable.xcstrings and rewrites the block between the
COVERAGE markers in README.md. Run it yourself, or let the pre-commit hook do
it (scripts/install-hooks.sh).

Coverage is simply "keys with a translated entry / total keys". That only reads
honestly because every key carries an explicit entry for its own source
language too — English and Romanian source strings are stored, not left to
fall back silently. Keep it that way: a catalog that relies on fallback would
report English at ~70% and mislead every contributor who looks at the table.

Exit code 1 with --check when README.md is out of date, so CI can catch a
commit that forgot to regenerate it.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOG = ROOT / "TopPresenter" / "Localizable.xcstrings"
README = ROOT / "README.md"

START = "<!-- i18n-coverage:start -->"
END = "<!-- i18n-coverage:end -->"

# Display order and endonyms — a language is named the way its own speakers
# write it, so a contributor can find theirs without reading English.
LANGUAGES = [
    ("en", "English", "🇬🇧"),
    ("ro", "Română", "🇷🇴"),
    ("es", "Español", "🇪🇸"),
    ("fr", "Français", "🇫🇷"),
    ("de", "Deutsch", "🇩🇪"),
    ("ru", "Русский", "🇷🇺"),
]

BAR_WIDTH = 24


def translatable(key: str) -> bool:
    """Keys with no words are the same in every language.

    `%lld`, `%@ / %@`, `%lld×%lld`, `Aa`, `https://…` carry nothing to translate.
    Counting them would drag every language's percentage down and send
    contributors hunting for gaps that do not exist.
    """
    stripped = re.sub(r"%(?:lld|@|%)", "", key)
    return bool(re.search(r"[^\W\d_]{2,}", stripped, re.UNICODE))


def coverage() -> tuple[dict[str, int], int]:
    data = json.loads(CATALOG.read_text(encoding="utf-8"))
    strings = {k: v for k, v in (data.get("strings") or {}).items() if translatable(k)}
    total = len(strings)
    counts: dict[str, int] = {code: 0 for code, _, _ in LANGUAGES}
    for entry in strings.values():
        for code, unit in (entry.get("localizations") or {}).items():
            if code not in counts:
                continue
            state = (unit.get("stringUnit") or {}).get("state")
            value = (unit.get("stringUnit") or {}).get("value")
            if state == "translated" and value:
                counts[code] += 1
    return counts, total


def render(counts: dict[str, int], total: int) -> str:
    lines = [
        START,
        "",
        f"**{total} translatable strings.** Regenerated on every commit — do not edit by hand.",
        "",
        "| | Language | Progress | Done |",
        "|---|---|---|---|",
    ]
    for code, name, flag in LANGUAGES:
        n = counts.get(code, 0)
        pct = (n * 100 // total) if total else 0
        filled = round(BAR_WIDTH * n / total) if total else 0
        bar = "█" * filled + "░" * (BAR_WIDTH - filled)
        done = "✅" if n == total else f"{n}/{total}"
        lines += [f"| {flag} | **{name}** (`{code}`) | `{bar}` {pct}% | {done} |"]
    lines += ["", END]
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="exit 1 if README.md is stale instead of rewriting it")
    args = ap.parse_args()

    counts, total = coverage()
    if total == 0:
        print("i18n: catalog is empty", file=sys.stderr)
        return 1

    block = render(counts, total)
    text = README.read_text(encoding="utf-8")
    if START not in text or END not in text:
        print(f"i18n: README.md is missing the {START} / {END} markers", file=sys.stderr)
        return 1

    head, rest = text.split(START, 1)
    _, tail = rest.split(END, 1)
    updated = head + block + tail

    if updated == text:
        return 0
    if args.check:
        print("i18n: README.md coverage table is stale — run scripts/i18n_coverage.py",
              file=sys.stderr)
        return 1
    README.write_text(updated, encoding="utf-8")
    print("i18n: README.md coverage table updated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
