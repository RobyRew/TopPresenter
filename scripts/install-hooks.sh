#!/usr/bin/env bash
# Installs the repo's git hooks. Run once after cloning:
#
#     ./scripts/install-hooks.sh
#
# Git does not version hooks, so this points core.hooksPath at scripts/hooks/
# instead of copying files into .git/ — that way an update to a hook reaches
# everyone through a normal pull.
set -euo pipefail

cd "$(dirname "$0")/.."
git config core.hooksPath scripts/hooks
chmod +x scripts/hooks/* 2>/dev/null || true
echo "Hooks installed (core.hooksPath = scripts/hooks)."
echo "  pre-commit → regenerates the README translation table"
