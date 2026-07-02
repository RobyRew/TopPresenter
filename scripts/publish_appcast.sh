#!/usr/bin/env bash
#
# publish_appcast.sh — EdDSA-sign a release zip and build ./site/appcast.xml for
# GitHub Pages. The workflow then deploys ./site via actions/deploy-pages — there is
# NO gh-pages branch; the feed is deployed straight from CI (source = GitHub Actions).
# Reusable across macOS apps (copy this file + wire the Pages steps; see UPDATES.md).
#
# Required env:
#   ZIP            path to the packaged app zip (e.g. TopPresenter-0.1.0.zip)
#   DOWNLOAD_URL   public URL where that zip is downloadable (GitHub release asset)
#   SHORT_VERSION  human version shown to users (e.g. 0.1.0 or 0.1.0-alpha.3)
#   BUILD_VERSION  monotonic CFBundleVersion Sparkle compares (e.g. the CI run number)
#   FEED_URL       the live appcast URL — fetched first so prior items are preserved
#                  (Pages deploys replace the whole site; there's no branch to accrue on)
#   CHANNEL        "" for stable, or "beta"
#   NOTES          release notes (plain text / HTML)
#   SPARKLE_PRIVATE_KEY   the EdDSA private key (secret)
#   SPARKLE_VERSION       Sparkle tools version to fetch (default 2.9.3)
#   MAX_ITEMS             keep at most N items in the appcast (default 40)
#
set -euo pipefail

: "${ZIP:?}" "${DOWNLOAD_URL:?}" "${SHORT_VERSION:?}" "${BUILD_VERSION:?}" "${FEED_URL:?}"
: "${SPARKLE_PRIVATE_KEY:?}"
CHANNEL="${CHANNEL:-}"
NOTES="${NOTES:-}"
SPARKLE_VERSION="${SPARKLE_VERSION:-2.9.3}"
MAX_ITEMS="${MAX_ITEMS:-40}"

# 1) Fetch Sparkle CLI tools (sign_update) matching the framework version.
curl -sL "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" -o sparkle.tar.xz
mkdir -p sparkletools && tar -xJf sparkle.tar.xz -C sparkletools

# 2) EdDSA-sign the zip -> `sparkle:edSignature="..." length="..."`
printf '%s' "$SPARKLE_PRIVATE_KEY" > sparkle_ed_key
SIG_LINE="$(sparkletools/bin/sign_update "$ZIP" --ed-key-file sparkle_ed_key)"
rm -f sparkle_ed_key
ED_SIG="$(printf '%s' "$SIG_LINE" | sed -n 's/.*edSignature="\([^"]*\)".*/\1/p')"
LENGTH="$(printf '%s' "$SIG_LINE" | sed -n 's/.*length="\([^"]*\)".*/\1/p')"
[ -z "$LENGTH" ] && LENGTH="$(stat -f%z "$ZIP" 2>/dev/null || stat -c%s "$ZIP")"

# 3) Seed ./site with the CURRENTLY PUBLISHED appcast so older items survive this
#    deploy (each Pages deploy replaces the whole site). 404/none -> start fresh.
mkdir -p site
curl -sfL "$FEED_URL" -o site/appcast.xml || rm -f site/appcast.xml

# 4) Insert/replace this version's <item> at the top of the channel.
ED_SIG="$ED_SIG" LENGTH="$LENGTH" DOWNLOAD_URL="$DOWNLOAD_URL" \
SHORT_VERSION="$SHORT_VERSION" BUILD_VERSION="$BUILD_VERSION" CHANNEL="$CHANNEL" \
NOTES="$NOTES" MAX_ITEMS="$MAX_ITEMS" APPCAST="site/appcast.xml" \
python3 "$(dirname "$0")/appcast_upsert.py"

# 5) A tiny landing page so the Pages root isn't a 404.
cat > site/index.html <<'HTML'
<!doctype html><meta charset="utf-8"><title>TopPresenter updates</title>
<p>TopPresenter Sparkle update feed: <a href="appcast.xml">appcast.xml</a></p>
HTML

echo "Built site/appcast.xml (channel='${CHANNEL:-stable}', version=${SHORT_VERSION})."
