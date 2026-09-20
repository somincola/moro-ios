#!/usr/bin/env python3
"""Create Any/Dark character icons from the selected, preserved artwork."""

import argparse
import hashlib
import json
from pathlib import Path
import runpy
import shutil

import numpy as np
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "moro/Resources/Assets.xcassets"
REVIEW = ROOT / "docs/design/app-icon-dark-mode/character-icons"
ORIGINALS = ROOT / "docs/design/app-icon-dark-mode/source-originals"
SHARED = runpy.run_path(str(ROOT / "scripts/generate-dark-app-icons.py"))
ICONS = [
    ("AppleGummy", "applegummy", "苹果软糖"),
    ("ZebraPrint", "zebraprint", "斑马印刷"),
    ("NotAwake", "notawake", "还没醒"),
]


def dark_variant(source, slug):
    rgb = np.asarray(source, dtype=np.float32)
    r, g, b = rgb.transpose(2, 0, 1)
    if slug == "applegummy":
        core = g >= r - 8
        top, bottom, grain = [46, 24, 37], [24, 17, 24], 0.18
    elif slug == "zebraprint":
        core = (r - g < 12) & (r - b < 25)
        top, bottom, grain = [78, 41, 36], [51, 29, 28], 0.35
    elif slug == "notawake":
        core = ((b > r + 25) & (b > g * 1.1)) | (rgb.max(axis=-1) < 95)
        core = SHARED["remove_small_islands"](core, minimum=18)
        top, bottom, grain = [68, 53, 32], [39, 31, 23], 0.25
    else:
        raise ValueError(slug)
    core = SHARED["fill_holes"](core)
    background = SHARED["border_color"](rgb)
    foreground, alpha = SHARED["matte"](rgb, core, background, preserve_holes=False)
    levels = np.linspace(top, bottom, 1024, dtype=np.float32)[:, None, :]
    # Keep the original backdrop's grain and tonal variation in the darker hue.
    backdrop = np.clip(levels + grain * (rgb - background), 0, 255)
    result = foreground * alpha[..., None] + backdrop * (1 - alpha[..., None])
    result = np.clip(result.round(), 0, 255).astype(np.uint8)
    assert np.array_equal(result[core], np.asarray(source)[core])
    return Image.fromarray(result), alpha


def write_contents(folder, slug, preview=False):
    prefix = "appicon-preview" if preview else "appicon"
    suffix = "" if preview else "-1024"
    common = {"idiom": "universal", "scale": "1x"} if preview else {
        "idiom": "universal", "platform": "ios", "size": "1024x1024"
    }
    images = []
    for dark in (False, True):
        entry = {"filename": f"{prefix}-{slug}{'-dark' if dark else ''}{suffix}.png", **common}
        if dark:
            entry["appearances"] = [{"appearance": "luminosity", "value": "dark"}]
        images.append(entry)
    (folder / "Contents.json").write_text(
        json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n"
    )


def comparison(destination):
    canvas = Image.new("RGBA", (24 + len(ICONS) * 568, 650), "#121418")
    draw = ImageDraw.Draw(canvas)
    path = "/System/Library/Fonts/STHeiti Medium.ttc"
    title = ImageFont.truetype(path, 30)
    heading = ImageFont.truetype(path, 24)
    body = ImageFont.truetype(path, 17)
    draw.text((28, 26), "Moro · 三款新图标 / 原版 + 深色外观", font=title, fill="#F0EEE8")
    draw.text((28, 77), "保留原来的造型、位置和比例；仅调整深色背景。", font=body, fill="#BABCC0")
    for i, (name, slug, label) in enumerate(ICONS):
        x, y = 24 + i * 568, 122
        draw.rounded_rectangle((x, y, x + 544, y + 477), radius=18,
                               fill="#1D2025", outline="#363940")
        draw.text((x + 20, y + 18), label, font=heading, fill="#F0EEE8")
        for index, dark in enumerate((False, True)):
            icon = Image.open(ASSETS / f"AppIcon{name}.appiconset" /
                              f"appicon-{slug}{'-dark' if dark else ''}-1024.png")
            tx = x + 20 + index * 264
            canvas.alpha_composite(SHARED["icon_tile"](icon, 240), (tx, y + 66))
            draw.text((tx, y + 322), "Dark" if dark else "原版 · Any", font=body, fill="#DADBDC")
            canvas.alpha_composite(SHARED["icon_tile"](icon, 60), (tx, y + 376))
            draw.text((tx + 76, y + 394), "60 px", font=body, fill="#BABCC0")
    draw.text((28, 617), "成图 1024 × 1024；圆角仅用于预览。", font=body, fill="#BABCC0")
    destination.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(destination, optimize=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preview", type=Path, help="Optional comparison image output path")
    args = parser.parse_args()
    REVIEW.mkdir(parents=True, exist_ok=True)
    report = []
    for name, slug, title in ICONS:
        source_path = ORIGINALS / f"appicon-{slug}-1024.png"
        source = Image.open(source_path).convert("RGB")
        assert source.size == (1024, 1024)
        dark, alpha = dark_variant(source, slug)
        folder = ASSETS / f"AppIcon{name}.appiconset"
        preview = ASSETS / f"AppIconPreview{name}.imageset"
        folder.mkdir(parents=True, exist_ok=True)
        preview.mkdir(parents=True, exist_ok=True)
        # Copy bytes rather than re-encode the approved Any artwork.
        shutil.copyfile(source_path, folder / source_path.name)
        dark.save(folder / f"appicon-{slug}-dark-1024.png", optimize=True)
        for image, suffix in ((source, ""), (dark, "-dark")):
            image.resize((240, 240), Image.Resampling.LANCZOS).save(
                preview / f"appicon-preview-{slug}{suffix}.png", optimize=True
            )
        write_contents(folder, slug)
        write_contents(preview, slug, preview=True)
        y, x = np.where(alpha > 0.5)
        bounds = [int(x.min()), int(y.min()), int(x.max()) + 1, int(y.max()) + 1]
        report.append({"name": title, "asset": f"AppIcon{name}",
                       "any_sha256": hashlib.sha256(source_path.read_bytes()).hexdigest(),
                       "subject_bounds": bounds,
                       "subject_percent": [round((bounds[2] - bounds[0]) / 10.24, 1),
                                           round((bounds[3] - bounds[1]) / 10.24, 1)],
                       "foreground_core_preserved": True})
        print(f"AppIcon{name}: approved Any copied unchanged; Dark and both previews generated")
    (REVIEW / "metrics.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    if args.preview:
        comparison(args.preview)


if __name__ == "__main__":
    main()
