# TopPresenter — app icon assets

Liquid Glass worship-presentation mark: a frosted-glass "slide" panel with a
luminous gold cross and presentation lines, on a deep indigo→violet gradient.

## Files
| File | Purpose |
|------|---------|
| `TopPresenter.svg` | Master artwork (1024², flattened). Edit this, then re-render. |
| `TopPresenter-1024.png` | 1024² raster master (rendered from the SVG). |
| `AppIcon.iconset/` | All macOS sizes (16–1024, @1x/@2x). |
| `icon-layers/background.svg` | Full-bleed gradient layer — Icon Composer background. |
| `icon-layers/foreground.svg` | Glass panel + cross + lines (transparent) — Icon Composer foreground. |

The shipping icon is **`../TopPresenter/AppIcon.icon`** — a real Icon Composer
bundle, wired by `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`. There is no
hand-made `.icns` any more: `actool` generates one from the `.icon` at build time.

## Two things that were wrong, so they don't come back
1. **The `.icon` lived inside `Assets.xcassets/`.** An Icon Composer bundle is a
   top-level target resource, NOT an asset-catalog member — in there `actool`
   ignored it and emitted no `Assets.car` at all. It belongs beside
   `Assets.xcassets`, not inside it.
2. **`INFOPLIST_KEY_CFBundleIconFile = AppIcon` was still set** (step 5 below was
   never finished), so macOS used the hand-rolled `TopPresenter/AppIcon.icns`
   instead. That file was `iconutil` over a full-bleed 1024² PNG, so its squircle
   ran edge to edge with **no margin** and the app icon rendered visibly larger
   than every other icon beside it. Icon Composer applies the correct macOS
   squircle and inset; `sips` + `iconutil` over a flat PNG cannot.

## What the build produces now
| Output | Contents |
|--------|----------|
| `Assets.car` | The icon at 32/64/128/256/512/1024 **plus** the layered source (background, foreground, gradients) that Tahoe renders as real Liquid Glass. This is what macOS resolves through `CFBundleIconName`. |
| `AppIcon.icns` | Auto-generated legacy fallback, 16–256 px. Do not add one by hand — a checked-in `AppIcon.icns` collides with this on the same output path. |

## Re-render the raster masters after editing `TopPresenter.svg`
```bash
cd Logo
qlmanage -t -s 1024 -o . TopPresenter.svg && mv TopPresenter.svg.png TopPresenter-1024.png
sips -z 256 256 TopPresenter-1024.png --out ../icon.png
```
The `AppIcon.iconset/` folder is legacy — kept only as a reference render. It no
longer feeds the app.

## Editing the `.icon` (macOS Tahoe — Icon Composer)
The bundle is authored in Apple's **Icon Composer** GUI (Xcode 26+) and cannot be
generated from the command line. Steps:

1. Open **Icon Composer** (Xcode ▸ Open Developer Tool ▸ Icon Composer).
2. Open **`../TopPresenter/AppIcon.icon`**, or start a new document and drag
   **`icon-layers/background.svg`** onto the background with
   **`icon-layers/foreground.svg`** as a floating layer.
3. Turn on **Liquid Glass** for the foreground (specular highlight + depth); tune
   blur/translucency to taste. Light + dark + clear variants auto-derive.
4. Export/save as **`TopPresenter/AppIcon.icon`** — beside `Assets.xcassets`,
   never inside it.
5. Nothing to change in build settings: `ASSETCATALOG_COMPILER_APPICON_NAME`
   already points at it, and `INFOPLIST_KEY_CFBundleIconFile` must stay absent.

On macOS Tahoe the system then renders the icon with the real Liquid Glass
material; earlier macOS falls back to the baked `.icns`.
