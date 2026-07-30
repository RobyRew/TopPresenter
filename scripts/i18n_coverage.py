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

Exit code 1 — in EITHER mode — when the base language is incomplete. English is
the development region (`CFBundleDevelopmentRegion`) and the catalog's
`sourceLanguage`, so every other language falls back to it. A key with no
English entry falls past English to the raw key text, which in this codebase is
written in Romanian: a German user reading Romanian is the symptom, an empty
`en` slot is the cause. This was a percentage in a table that nobody had to act
on, and 53 strings accumulated behind it. It is a failure now.
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

# The development region every other language falls back to. Not a preference:
# it is CFBundleDevelopmentRegion and the catalog's sourceLanguage.
BASE_LANGUAGE = "en"


def translatable(key: str) -> bool:
    """Keys with no words are the same in every language.

    `%lld`, `%@ / %@`, `%lld×%lld`, `Aa`, `https://…` carry nothing to translate.
    Counting them would drag every language's percentage down and send
    contributors hunting for gaps that do not exist.
    """
    stripped = re.sub(r"%(?:lld|@|%)", "", key)
    return bool(re.search(r"[^\W\d_]{2,}", stripped, re.UNICODE))


def untranslated(code: str) -> list[str]:
    """Translatable keys with no usable entry for `code`."""
    data = json.loads(CATALOG.read_text(encoding="utf-8"))
    missing = []
    for key, entry in (data.get("strings") or {}).items():
        if not translatable(key):
            continue
        unit = ((entry.get("localizations") or {}).get(code) or {}).get("stringUnit") or {}
        if unit.get("state") != "translated" or not unit.get("value"):
            missing.append(key)
    return missing


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

    stale = updated != text
    if stale and not args.check:
        README.write_text(updated, encoding="utf-8")
        print("i18n: README.md coverage table updated")

    # The base language is a correctness gate, not a statistic: an empty `en`
    # slot means EVERY language falls through to the raw key text.
    gaps = untranslated(BASE_LANGUAGE)
    if gaps:
        print(f"i18n: {len(gaps)} string(s) have no {BASE_LANGUAGE} translation. "
              f"{BASE_LANGUAGE} is the base language every other one falls back to, "
              f"so these show as raw key text in every locale:", file=sys.stderr)
        for key in gaps[:20]:
            print(f"  - {key}", file=sys.stderr)
        if len(gaps) > 20:
            print(f"  … and {len(gaps) - 20} more", file=sys.stderr)
        return 1

    if stale and args.check:
        print("i18n: README.md coverage table is stale — run scripts/i18n_coverage.py",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
