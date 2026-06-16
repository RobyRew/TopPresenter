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

The shipping icon today is **`../TopPresenter/AppIcon.icns`** (wired via
`INFOPLIST_KEY_CFBundleIconFile = AppIcon`) — works Sonoma → latest.

## Re-render after editing `TopPresenter.svg`
```bash
cd Logo
qlmanage -t -s 1024 -o . TopPresenter.svg && mv TopPresenter.svg.png TopPresenter-1024.png
rm -rf AppIcon.iconset && mkdir AppIcon.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s TopPresenter-1024.png --out "AppIcon.iconset/icon_${s}x${s}.png"
  sips -z $((s*2)) $((s*2)) TopPresenter-1024.png --out "AppIcon.iconset/icon_${s}x${s}@2x.png"
done
iconutil -c icns AppIcon.iconset -o ../TopPresenter/AppIcon.icns
sips -z 256 256 TopPresenter-1024.png --out ../icon.png
```

## True Liquid Glass `.icon` (macOS Tahoe — Icon Composer)
The `.icon` bundle is authored in Apple's **Icon Composer** GUI (Xcode 26+) — it
can't be generated from the command line. Steps:

1. Open **Icon Composer** (Xcode ▸ Open Developer Tool ▸ Icon Composer).
2. New document → drag **`icon-layers/background.svg`** onto the background and
   **`icon-layers/foreground.svg`** as a floating layer.
3. Turn on **Liquid Glass** for the foreground (specular highlight + depth);
   tune blur/translucency to taste. Light + dark + clear variants auto-derive.
4. Export **`AppIcon.icon`** into `TopPresenter/Assets.xcassets/`.
5. In build settings set `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` and drop
   `INFOPLIST_KEY_CFBundleIconFile` (keep the `.icns` only as a pre-Tahoe fallback).

On macOS Tahoe the system then renders the icon with the real Liquid Glass
material; earlier macOS falls back to the baked `.icns`.
