#!/usr/bin/env python3
"""Build the TopPresenter theme pack from one base theme + a media library.

Every theme in the pack is the SAME layout with a different surface: same box
order, same alignment rules, same profiles. That is deliberate. An operator
learns one arrangement and then chooses a mood, instead of relearning where the
reference sits every time they switch theme.

What varies is what actually changes how a slide READS:

  background   the surface itself
  fontSize     smaller on busy photography, larger on flat colour
  weight       heavier where the background competes
  shadow       radius and opacity scale with how noisy the background is
  textColor    dark on the daylight theme, light everywhere else
  autoFit      on over photography, where a long verse cannot be allowed to
               overflow into the horizon line

The base is Default.tptheme — the one with the clock removed. Deriving from it
means a fix to the base propagates to the whole pack on the next build.
"""

from __future__ import annotations

import json
import pathlib
import shutil
import sys
import uuid

ROOT = pathlib.Path(__file__).resolve().parent.parent
BASE = ROOT / "ExtraAssets" / "ThemesV2" / "Default.tptheme" / "theme.json"
OUT = ROOT / "ExtraAssets" / "ThemesV2"

BACKGROUNDS = pathlib.Path("/Users/cosmincalin/Documents/Personal/Media/Backgrounds")
HORIZONTAL = BACKGROUNDS / "Horizontal"

# Filled in by the caller: where the generated art and transcoded clips landed.
GENERATED = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else None
VIDEO1080 = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else None

# name, source file, media kind, and the typography that suits it.
#   src kinds: "gen" generated art · "photo" from Horizontal · "video" transcoded
THEMES = [
    # ---- generated surfaces: flat, quiet, text-first --------------------
    ("Grafit",          "gen",   "Grafit.jpg",          dict(fontSize=138, weight="regular",  shadow=6,  shadowAlpha="80", autofit=False)),
    ("Miezul nopții",   "gen",   "Miezul-noptii.jpg",   dict(fontSize=134, weight="regular",  shadow=10, shadowAlpha="B3", autofit=False)),
    ("Indigo",          "gen",   "Indigo.jpg",          dict(fontSize=132, weight="medium",   shadow=12, shadowAlpha="B3", autofit=False)),
    ("Smarald",         "gen",   "Smarald.jpg",         dict(fontSize=132, weight="regular",  shadow=11, shadowAlpha="B3", autofit=False)),
    ("Purpuriu",        "gen",   "Purpuriu.jpg",        dict(fontSize=130, weight="regular",  shadow=12, shadowAlpha="C0", autofit=False)),
    ("Răsărit",         "gen",   "Rasarit.jpg",         dict(fontSize=130, weight="medium",   shadow=14, shadowAlpha="C0", autofit=False)),
    ("Auroră",          "gen",   "Aurora.jpg",          dict(fontSize=132, weight="regular",  shadow=12, shadowAlpha="B3", autofit=False)),
    # The daylight theme. Dark text on near-white is the only combination that
    # survives a projector losing to sunlight, so it inverts everything.
    ("Lumină",          "gen",   "Lumina.jpg",          dict(fontSize=128, weight="semibold", shadow=0,  shadowAlpha="00",
                                                             textColor="16181D", shadowOn=False, autofit=False)),

    # ---- photography: busier, so smaller and heavier, with autofit ------
    ("Cer înstelat",    "photo", "Cielo despejado Nepal.jpg", dict(fontSize=120, weight="semibold", shadow=18, shadowAlpha="CC", autofit=True, scrim=0.8)),
    ("Munți",           "photo", "IMG_4333.JPG",              dict(fontSize=118, weight="semibold", shadow=18, shadowAlpha="CC", autofit=True, scrim=0.62)),
    ("Peșteră",         "photo", "74b77bf453ffffcbf203e187ac54bcfebec9756a3cf38cc16569af75d700bb42.jpg",
                                                              dict(fontSize=118, weight="semibold", shadow=20, shadowAlpha="D9", autofit=True, scrim=0.66)),
    ("Palmieri",        "photo", "12f4645e8ae9988f330497f202e6e5f5d1b15d741fe760f9eb93e85bcbef69ac.jpg",
                                                              dict(fontSize=118, weight="semibold", shadow=18, shadowAlpha="CC", autofit=True, scrim=0.7)),
    ("Țărm",            "photo", "d619367119fc2c52a05919299d744516268dc509799f4b4bb321aaa8d1aed42f.jpg",
                                                              dict(fontSize=118, weight="semibold", shadow=18, shadowAlpha="CC", autofit=True, scrim=0.66)),
    ("Turcoaz",         "photo", "Playa azul.jpg",            dict(fontSize=118, weight="semibold", shadow=20, shadowAlpha="D9", autofit=True, scrim=0.6)),
    ("Geometric",       "photo", "1010881.jpg",               dict(fontSize=122, weight="semibold", shadow=18, shadowAlpha="CC", autofit=True, scrim=0.68)),

    # ---- motion --------------------------------------------------------
    ("Galaxie",         "video", "Galaxy - 19342.mp4",     dict(fontSize=128, weight="medium",   shadow=14, shadowAlpha="C0", autofit=True)),
    ("Particule",       "video", "Particles - 26909.mp4",  dict(fontSize=128, weight="medium",   shadow=14, shadowAlpha="C0", autofit=True)),
    ("Cerneală",        "video", "Ink - 23730.mp4",        dict(fontSize=126, weight="semibold", shadow=16, shadowAlpha="CC", autofit=True, scrim=0.78)),
    ("Minimal",         "video", "Minimalism - 14124.mp4", dict(fontSize=130, weight="regular",  shadow=12, shadowAlpha="B3", autofit=True)),
    ("Abstract",        "video", "Abstract - 11727.mp4",   dict(fontSize=128, weight="medium",   shadow=14, shadowAlpha="C0", autofit=True, scrim=0.82)),
]


def source_path(kind: str, filename: str) -> pathlib.Path:
    if kind == "gen":
        return GENERATED / filename
    if kind == "video":
        return VIDEO1080 / filename
    return HORIZONTAL / filename


def build(name: str, kind: str, filename: str, style: dict) -> tuple[str, int]:
    base = json.loads(BASE.read_text(encoding="utf-8"))
    src = source_path(kind, filename)
    if not src.exists():
        raise FileNotFoundError(src)

    pkg = OUT / f"{name}.tptheme"
    if pkg.exists():
        shutil.rmtree(pkg)
    (pkg / "media").mkdir(parents=True)

    # Keep the extension, drop the hash-soup names the downloads came with:
    # a theme's media file shows up in the app, so it should be readable.
    ext = src.suffix.lower()
    asset_name = f"{name}{ext}"
    shutil.copy2(src, pkg / "media" / asset_name)

    media_type = "video" if kind == "video" else "image"
    base["name"] = name
    base["themeID"] = str(uuid.uuid4()).upper()
    base["assets"] = [{"file": asset_name, "mediaType": media_type, "slot": "background"}]

    p = base["payload"]
    p["useBackgroundImage"] = True
    p["backgroundMediaTypeRaw"] = media_type
    p["backgroundColorHex"] = "000000"

    # The scrim.
    #
    # `backgroundLayer` draws the colour FIRST and the media over it, so black
    # underneath plus a background opacity below 1 is a dimmer — and it is the
    # difference between a theme that looks nice in a screenshot and one you can
    # actually read a verse on. Photographs are the problem: Munți puts the
    # lyric over a bright pink sky, Peșteră over a lit cave mouth. A drop shadow
    # cannot rescue white text on a light background; taking 30% out of the
    # picture can.
    #
    # Generated surfaces are already built to lose, so they take no scrim.
    scrim = style.get("scrim")
    if scrim:
        p["backgroundEnabled"] = True
        p["backgroundOpacity"] = scrim
    else:
        p["backgroundEnabled"] = False
        p["backgroundOpacity"] = 1

    p["fontSize"] = style["fontSize"]
    p["globalWeightRaw"] = style["weight"]
    p["autoFitVerseFont"] = style["autofit"]
    p["textColorHex"] = style.get("textColor", "FFFFFF")
    p["shadowEnabled"] = style.get("shadowOn", True)
    p["shadowRadius"] = style["shadow"]
    p["shadowColorHex"] = "000000" + style["shadowAlpha"]

    (pkg / "theme.json").write_text(
        json.dumps(base, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    size = sum(f.stat().st_size for f in pkg.rglob("*") if f.is_file())
    return name, size


def main() -> int:
    if not BASE.exists():
        print(f"base theme missing: {BASE}")
        return 1
    total = 0
    print(f"{'theme':18} {'kind':6} size")
    for name, kind, filename, style in THEMES:
        try:
            n, size = build(name, kind, filename, style)
        except FileNotFoundError as exc:
            print(f"{name:18} {kind:6} MISSING {exc}")
            continue
        total += size
        print(f"{n:18} {kind:6} {size/1_048_576:6.1f} MB")
    default_size = sum(f.stat().st_size for f in (OUT / "Default.tptheme").rglob("*") if f.is_file())
    print(f"\n{len(THEMES)} themes + Default · {(total + default_size)/1_048_576:.0f} MB total")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
