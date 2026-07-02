# Auto-updates (Sparkle) — how it works & one-time setup

TopPresenter updates itself with **[Sparkle 2](https://sparkle-project.org)** — the industry
standard for macOS apps distributed outside the App Store. Binaries live on **GitHub Releases**;
a signed **appcast.xml** is published to **GitHub Pages** by CI; the app checks that feed on launch
and on a schedule, verifies each update's **EdDSA signature**, and installs + relaunches. This is the
same setup to reuse for every future macOS app (see *Reuse* below).

## What the user gets (already wired in the app)
- **Automatic checks** on launch + every 2 h (configurable) — Sparkle's scheduler.
- **Quiet prompt** → *Install & Relaunch* (or fully silent if they enable auto-download).
- **Opt out / cadence / beta channel / “Check now”** in **Settings ▸ Actualizări**.
- **Menu**: *TopPresenter ▸ Caută actualizări…* (beside About).
- **Roll back / reinstall any version**: Settings ▸ Actualizări ▸ **Toate versiunile…** (reads the
  appcast, installs a chosen release through Sparkle — signature-verified).

## ✅ Status for THIS repo (TopPresenter) — already configured
The one-time setup below is **done**: EdDSA keys generated, `SUPublicEDKey` set in `Info.plist`,
`SPARKLE_PRIVATE_KEY` added as a repo secret, GitHub Pages serving the `gh-pages` branch at
`https://robyrew.github.io/TopPresenter/`. **Just push to `main`** and CI publishes the appcast; the app
updates itself. Signing is **ad-hoc for now** (see note below — Gatekeeper still says "unidentified
developer" on first open of each version; upgrade to Developer ID later for a clean, silent experience).
The steps below are kept for reference and for reusing this setup in future apps.

## One-time setup (do this once per repo)
1. **Get Sparkle's tools** (matching the framework version, currently 2.9.3):
   `curl -L https://github.com/sparkle-project/Sparkle/releases/download/2.9.3/Sparkle-2.9.3.tar.xz | tar xJ`
   → gives `bin/generate_keys`, `bin/sign_update`, `bin/generate_appcast`.
2. **Generate the signing keys**: `./bin/generate_keys`
   - prints your **public** key → paste it into `Info.plist` under `SUPublicEDKey`
     (replace `REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY`).
   - stores the **private** key in your login Keychain. Export it for CI:
     `./bin/generate_keys -x sparkle_private_key.txt` → copy the file's contents.
3. **Add the repo secret**: GitHub ▸ Settings ▸ Secrets and variables ▸ Actions ▸ New secret
   `SPARKLE_PRIVATE_KEY` = the exported private key. (Never commit it.)
   *Until this secret exists, the CI appcast step no-ops and CI stays green.*
4. **Enable GitHub Pages**: push once so CI creates the `gh-pages` branch (it publishes
   `appcast.xml` there), then Settings ▸ Pages ▸ Source = *Deploy from branch* → `gh-pages` / root.
5. **Confirm the feed URL**: `Info.plist ▸ SUFeedURL` = `https://<owner>.github.io/<repo>/appcast.xml`
   (currently `https://robyrew.github.io/TopPresenter/appcast.xml`).

That's it. Every push to `main` publishes a **beta** appcast item; every `vX.Y.Z` tag publishes a
**stable** one. Versions are compared by a monotonic `CFBundleVersion` (CI sets it to the run number).

## Signing note (current: ad-hoc / "unsigned")
CI ad-hoc-signs the app (`CODE_SIGN_IDENTITY="-"`) so the sandbox + Sparkle installer work with **no
Apple certificates**. Updates install correctly, but macOS Gatekeeper still shows “unidentified
developer” on first open of each version (right-click → Open, or `xattr -cr TopPresenter.app`).

### Later: Developer ID + notarization (silent, Gatekeeper-clean) — drop-in, no app-code change
You already have an Apple team (`FJHAUWNNBH`). When ready:
- Export your **Developer ID Application** cert (`.p12`) + create an **App Store Connect API key**;
  add both as repo secrets.
- In CI: import the cert into a temp keychain; change the build's `CODE_SIGN_IDENTITY` to
  `"Developer ID Application"` with `--options runtime`; after packaging run
  `xcrun notarytool submit … --wait` then `xcrun stapler staple`.
- Nothing else changes — the appcast/Sparkle flow is identical.

## Reuse for future macOS apps
Copy, then redo steps 1–5 with that app's own keys/repo:
- App code: `Core/UpdateController.swift`, `Views/Settings/UpdatesSettingsTab.swift`,
  `Views/Updates/VersionsView.swift`, the `UpdaterCommands` in `Core/AppCommands.swift`, and the
  `TopPresenterApp` wiring (`@StateObject` + `.environmentObject` + the command).
- Config: the Sparkle keys in `Info.plist`; the `network.client` + Sparkle mach-lookup exceptions in
  the `.entitlements`; the Sparkle SPM dependency.
- CI: `scripts/publish_appcast.sh`, `scripts/appcast_upsert.py`, and the appcast steps in
  `.github/workflows/build-and-release.yml`.

## Verify end-to-end
1. Set the secret + public key + Pages, push twice (two different `github.run_number`s).
2. `https://<owner>.github.io/<repo>/appcast.xml` lists items with `sparkle:edSignature`.
3. Run an older build → within a few seconds it offers the update → Install & Relaunch → new version.
4. Settings ▸ Actualizări: toggle auto-checks off (no prompts); *Toate versiunile…* → install/downgrade.
5. Tamper with a zip → Sparkle refuses it (signature check works).
