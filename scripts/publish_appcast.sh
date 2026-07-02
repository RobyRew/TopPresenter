#!/usr/bin/env bash
#
# publish_appcast.sh — EdDSA-sign a release zip and publish/append it to the Sparkle
# appcast on the gh-pages branch. Reusable across macOS apps (copy this file + wire the
# two CI jobs; see UPDATES.md).
#
# Required env:
#   ZIP            path to the packaged app zip (e.g. TopPresenter-0.1.0.zip)
#   DOWNLOAD_URL   public URL where that zip is downloadable (GitHub release asset)
#   SHORT_VERSION  human version shown to users (e.g. 0.1.0 or 0.1.0-alpha.3)
#   BUILD_VERSION  monotonic CFBundleVersion Sparkle compares (e.g. the CI run number)
#   CHANNEL        "" for stable, or "beta"
#   NOTES          release notes (plain text / HTML)
#   REPO           owner/name (for the gh-pages clone)
#   SPARKLE_PRIVATE_KEY   the EdDSA private key (secret)
#   GITHUB_TOKEN          token with contents:write (for pushing gh-pages)
#   SPARKLE_VERSION       Sparkle tools version to fetch (default 2.9.3)
#   MAX_ITEMS             keep at most N items in the appcast (default 40)
#
set -euo pipefail

: "${ZIP:?}" "${DOWNLOAD_URL:?}" "${SHORT_VERSION:?}" "${BUILD_VERSION:?}" "${REPO:?}"
: "${SPARKLE_PRIVATE_KEY:?}" "${GITHUB_TOKEN:?}"
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

# 3) Check out the existing appcast from gh-pages (or start fresh).
rm -rf pages
if git clone --depth 1 --branch gh-pages "https://x-access-token:${GITHUB_TOKEN}@github.com/${REPO}.git" pages 2>/dev/null; then :; else
  mkdir pages && ( cd pages && git init -q && git checkout -qb gh-pages \
    && git remote add origin "https://x-access-token:${GITHUB_TOKEN}@github.com/${REPO}.git" )
fi

# 4) Insert/replace this version's <item> at the top of the channel (reliable via python).
ED_SIG="$ED_SIG" LENGTH="$LENGTH" DOWNLOAD_URL="$DOWNLOAD_URL" \
SHORT_VERSION="$SHORT_VERSION" BUILD_VERSION="$BUILD_VERSION" CHANNEL="$CHANNEL" \
NOTES="$NOTES" MAX_ITEMS="$MAX_ITEMS" APPCAST="pages/appcast.xml" \
python3 "$(dirname "$0")/appcast_upsert.py"

# 5) Commit + push.
cd pages
git add appcast.xml
git -c user.email="ci@toppresenter.local" -c user.name="TopPresenter CI" \
  commit -m "appcast: ${SHORT_VERSION}" || { echo "appcast unchanged"; exit 0; }
git push origin gh-pages
