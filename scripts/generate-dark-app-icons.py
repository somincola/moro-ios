#!/usr/bin/env python3
"""Build icon appearances and previews from preserved pixels (Pillow/NumPy)."""

from collections import deque
from pathlib import Path
import json

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "moro/Resources/Assets.xcassets"
REVIEW = ROOT / "docs/design/app-icon-dark-mode"
ORIGINALS = REVIEW / "source-originals"
ADJUSTED_SLUGS = {"liquidglass", "paintchaos", "risoglitch", "torncollage"}
ICONS = [
    ("AppIcon", "default", "默认"),
    ("AppIconRainbow", "rainbow", "彩虹"),
    ("AppIconLiquidGlass", "liquidglass", "液态玻璃"),
    ("AppIconPaintChaos", "paintchaos", "泼彩"),
    ("AppIconRisoGlitch", "risoglitch", "Riso"),
    ("AppIconTornCollage", "torncollage", "撕纸拼贴"),
]


def fill_holes(mask):
    """Keep enclosed foreground details when removing the outer backdrop."""
    padded = np.pad(mask, 1, constant_values=False)
    image = Image.fromarray(np.where(padded, 0, 255).astype(np.uint8)).copy()
    ImageDraw.floodfill(image, (0, 0), 128)
    return (np.asarray(image)[1:-1, 1:-1] != 128)


def propagate_colors(rgb, core, steps=5):
    """Extend nearby source colors to the few antialiased edge pixels."""
    color = rgb.copy()
    known = core.copy()
    for _ in range(steps):
        total = np.zeros_like(rgb)
        weight = np.zeros(core.shape, dtype=np.float32)
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            neighbor = np.roll(known, (dy, dx), axis=(0, 1))
            total += np.roll(color, (dy, dx), axis=(0, 1)) * neighbor[..., None]
            weight += neighbor
        new = ~known & (weight > 0)
        color[new] = total[new] / weight[new, None]
        known |= new
    return color, known


def matte(rgb, core, background, preserve_holes=True):
    """Unmix the old backdrop instead of leaving its color on the edge."""
    if preserve_holes:
        core = fill_holes(core)
    reference, nearby = propagate_colors(rgb, core)
    vector = reference - background
    denominator = np.sum(vector * vector, axis=-1)
    alpha = np.clip(
        np.sum((rgb - background) * vector, axis=-1)
        / np.maximum(denominator, 1), 0, 1
    )
    alpha[core] = 1
    alpha[~nearby | (alpha < 0.025)] = 0
    foreground = (rgb - background * (1 - alpha[..., None])) / np.maximum(
        alpha[..., None], 0.001
    )
    foreground[core] = rgb[core]
    return np.clip(foreground, 0, 255), alpha


def border_color(rgb):
    edge = np.concatenate((rgb[:8].reshape(-1, 3), rgb[-8:].reshape(-1, 3),
                           rgb[:, :8].reshape(-1, 3), rgb[:, -8:].reshape(-1, 3)))
    return np.median(edge, axis=0)


def remove_small_islands(mask, minimum=12):
    """Remove isolated paper grain, keeping the substantial printed shapes."""
    remaining = mask.copy()
    output = np.zeros_like(mask)
    height, width = mask.shape
    for y, x in zip(*np.nonzero(mask)):
        if not remaining[y, x]:
            continue
        queue = deque([(y, x)])
        remaining[y, x] = False
        component = []
        while queue:
            cy, cx = queue.popleft()
            component.append((cy, cx))
            for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                ny, nx = cy + dy, cx + dx
                if 0 <= ny < height and 0 <= nx < width and remaining[ny, nx]:
                    remaining[ny, nx] = False
                    queue.append((ny, nx))
        if len(component) >= minimum:
            ys, xs = zip(*component)
            output[ys, xs] = True
    return output


def rgba_image(foreground, alpha):
    output = np.dstack((foreground, alpha * 255)).round().clip(0, 255).astype(np.uint8)
    output[output[..., 3] == 0, :3] = 0
    return Image.fromarray(output)


def derive(rgb, slug):
    background = border_color(rgb)
    mean = rgb.mean(axis=-1)
    maximum = rgb.max(axis=-1)
    minimum = rgb.min(axis=-1)
    spread = maximum - minimum
    if slug == "default":
        core = np.linalg.norm(rgb - background, axis=-1) > 140
        foreground, alpha = matte(rgb, core, background)
        return foreground, alpha
    if slug == "rainbow":
        core = np.linalg.norm(rgb - background, axis=-1) > 145
        foreground, alpha = matte(rgb, core, background)
        # Raise only the violet ink; keep the six-band rainbow identity.
        violet = (foreground[..., 2] > foreground[..., 0] * 1.08) & (
            foreground[..., 0] > foreground[..., 1] * 1.6
        )
        foreground[violet] = foreground[violet] * 1.14 + [8, 6, 8]
        return np.clip(foreground, 0, 255), alpha
    if slug == "torncollage":
        r, g, b = rgb.transpose(2, 0, 1)
        lime = (g > r * 1.05) & (g > b * 2) & (g > 50)
        return matte(rgb, ~lime, background)
    if slug == "paintchaos":
        alpha = np.maximum(np.clip((spread - 9) / 23, 0, 1),
                           np.clip((mean - 26) / 65, 0, 1))
        alpha[alpha < 0.1] = 0
        alpha[fill_holes(alpha > 0.65)] = 1
        foreground = (rgb - background * (1 - alpha[..., None])) / np.maximum(
            alpha[..., None], 0.001
        )
        return np.clip(foreground, 0, 255), alpha
    if slug == "risoglitch":
        alpha = np.maximum(np.clip((160 - mean) / 65, 0, 1),
                           np.clip((spread - 60) / 45, 0, 1))
        keep = remove_small_islands(alpha > 0.15)
        alpha[~keep] = 0
        foreground = rgb.copy()
        neutral_ink = (spread < 48) & (mean < 155)
        shade = np.clip((mean - 28) * 0.35, -4, 35)
        foreground[neutral_ink] = (
            np.array([236, 228, 211]) - shade[neutral_ink, None]
        )
        return np.clip(foreground, 0, 255), alpha
    if slug == "liquidglass":
        # The closed chrome rim defines the existing silhouette. Fill its
        # surfaces while leaving open gaps around the trunk transparent.
        rim = (maximum > 118) | (mean > 62)
        image = Image.fromarray((rim * 255).astype(np.uint8))
        closed = image.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))
        core = fill_holes(np.asarray(closed) > 0)
        alpha = np.asarray(Image.fromarray((core * 255).astype(np.uint8)).filter(
            ImageFilter.GaussianBlur(0.45)
        ), dtype=np.float32) / 255
        alpha[alpha < 0.025] = 0
        foreground = np.clip(rgb * 1.04 + 7, 0, 255)
        return foreground, alpha
    raise ValueError(slug)


def centered_scale(image, scale):
    """Resample once; use premultiplied alpha to avoid dark edge fringes."""
    side = round(1024 * scale)
    has_alpha = image.mode == "RGBA"
    working = image.convert("RGBa") if has_alpha else image
    working = working.resize((side, side), Image.Resampling.LANCZOS)
    if has_alpha:
        working = working.convert("RGBA")
    if side >= 1024:
        offset = (side - 1024) // 2
        return working.crop((offset, offset, offset + 1024, offset + 1024))
    output = Image.new("RGBA", (1024, 1024))
    output.alpha_composite(working.convert("RGBA"), ((1024 - side) // 2,) * 2)
    return output


def clean_riso_alpha(alpha):
    # Ignore independent paper specks while retaining the connected print.
    keep = remove_small_islands(alpha > 0.5, minimum=1500)
    support = Image.fromarray((keep * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(5))
    return alpha * (np.asarray(support) > 0)


def extend_background(source, alpha, slug):
    """Fill the old foreground with a field and grain sampled from its backdrop.

    Keep original backdrop pixels outside the repair region; fit only background
    samples, so shrinking a flattened image never introduces a rectangular mat.
    """
    rgb = np.asarray(source, dtype=np.float32)
    mask = Image.fromarray((alpha * 255).round().astype(np.uint8))
    repair = mask.filter(ImageFilter.MaxFilter(61)).filter(ImageFilter.GaussianBlur(12))
    known = np.asarray(repair) < 2
    yy, xx = np.mgrid[-1:1:1024j, -1:1:1024j]
    design = np.stack((np.ones_like(xx), xx, yy, xx * xx, xx * yy, yy * yy), axis=-1)
    sample = known[::8, ::8]
    coefficients = np.linalg.lstsq(design[::8, ::8][sample], rgb[::8, ::8][sample], rcond=None)[0]
    field = design @ coefficients
    residual = (rgb - field)[known]
    # Reuse measured texture, with a fixed seed for reproducible builds.
    deviation = np.linalg.norm(residual, axis=-1)
    residual = residual[deviation < np.quantile(deviation, 0.98)]
    rng = np.random.default_rng(18092026)
    grain = residual[rng.integers(0, len(residual), (1024, 1024))]
    if slug == "torncollage":
        grain *= 0.18
    else:
        # Low-pass only the added grain; retained paper pixels are untouched.
        encoded = Image.fromarray(np.clip(grain + 128, 0, 255).astype(np.uint8))
        grain = (np.asarray(encoded.filter(ImageFilter.GaussianBlur(0.35)), dtype=np.float32) - 128) * 1.15
    fill = Image.fromarray(np.clip(field + grain, 0, 255).round().astype(np.uint8))
    return Image.composite(fill, source, repair)


def paint_subject_mesh():
    """Uniformly enlarge the white motif, smoothly returning to fixed splashes.

    The inner 270 px radius scales by 1.25. Outside 485 px all original pixels
    stay in place. Inverse mapping uses the same mesh for both appearances.
    """
    nodes = np.arange(0, 1025, 16, dtype=np.float64)
    dy, dx = np.meshgrid(nodes, nodes, indexing="ij")
    sx, sy = dx.copy(), dy.copy()
    for _ in range(80):
        radius = np.hypot(sx - 575, sy - 575)
        t = np.clip((radius - 270) / (485 - 270), 0, 1)
        weight = 1 - t * t * (3 - 2 * t)
        sx, sy = (dx - weight * (0.25 * (sx - 575) - 28),
                  dy - weight * (0.25 * (sy - 575) - 24))
    mesh = []
    for y in range(64):
        for x in range(64):
            quad = (sx[y, x], sy[y, x], sx[y + 1, x], sy[y + 1, x],
                    sx[y + 1, x + 1], sy[y + 1, x + 1], sx[y, x + 1], sy[y, x + 1])
            mesh.append(((x * 16, y * 16, (x + 1) * 16, (y + 1) * 16), quad))
    return mesh


def warp_paint(image, mesh):
    mode = image.mode
    working = image.convert("RGBa") if mode == "RGBA" else image
    output = working.transform((1024, 1024), Image.Transform.MESH, mesh, Image.Resampling.BICUBIC)
    return output.convert(mode)


def prepare_icon(source, slug):
    rgb = np.asarray(source, dtype=np.float32)
    foreground, alpha = derive(rgb, slug)
    original_dark = rgba_image(foreground, alpha)
    if slug == "liquidglass":
        return centered_scale(source, 1.22), centered_scale(original_dark, 1.22)
    if slug == "paintchaos":
        mesh = paint_subject_mesh()
        return warp_paint(source, mesh), warp_paint(original_dark, mesh)
    if slug in {"risoglitch", "torncollage"}:
        scale = 0.84 if slug == "risoglitch" else 0.80
        backdrop_alpha = alpha
        if slug == "risoglitch":
            alpha = clean_riso_alpha(alpha)
        backdrop = extend_background(source, backdrop_alpha, slug).convert("RGBA")
        # Retain the original thin paper edges and cast shadows in Any.
        margin = 7 if slug == "risoglitch" else 29
        edge = Image.fromarray((alpha * 255).round().astype(np.uint8))
        edge = edge.filter(ImageFilter.MaxFilter(margin)).filter(ImageFilter.GaussianBlur(1 if slug == "risoglitch" else 4))
        any_layer = source.convert("RGBA")
        any_layer.putalpha(edge)
        backdrop.alpha_composite(centered_scale(any_layer, scale))
        dark = centered_scale(rgba_image(foreground, alpha), scale)
        return backdrop.convert("RGB"), dark
    return source, original_dark


def dark_backdrop(size):
    levels = np.linspace(48, 23, size).round().astype(np.uint8)
    pixels = np.broadcast_to(levels[:, None, None], (size, size, 3)).copy()
    return Image.fromarray(pixels).convert("RGBA")


def save_preview(name, slug, source, dark):
    preview_name = "AppIconPreview" + ("Default" if slug == "default" else name.removeprefix("AppIcon"))
    folder = ASSETS / f"{preview_name}.imageset"
    filename = f"appicon-preview-{slug}.png"
    if slug in ADJUSTED_SLUGS:
        source.resize((240, 240), Image.Resampling.LANCZOS).save(folder / filename, optimize=True)
    dark_filename = f"appicon-preview-{slug}-dark.png"
    preview = dark_backdrop(240)
    preview.alpha_composite(dark.resize((240, 240), Image.Resampling.LANCZOS))
    preview.convert("RGB").save(folder / dark_filename, optimize=True)
    contents = {
        "images": [
            {"filename": filename, "idiom": "universal", "scale": "1x"},
            {"appearances": [{"appearance": "luminosity", "value": "dark"}],
             "filename": dark_filename, "idiom": "universal", "scale": "1x"},
        ],
        "info": {"author": "xcode", "version": 1},
    }
    (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def icon_tile(image, size, dark=False):
    canvas = Image.new("RGBA", (size, size))
    if dark:
        for y in range(size):
            value = round(48 - 25 * y / max(size - 1, 1))
            ImageDraw.Draw(canvas).line((0, y, size, y), fill=(value, value, value, 255))
    canvas.alpha_composite(image.convert("RGBA").resize((size, size), Image.Resampling.LANCZOS))
    scale = 4
    mask = Image.new("L", (size * scale, size * scale))
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size * scale - 1, size * scale - 1),
                                          radius=size * scale * 0.225, fill=255)
    canvas.putalpha(mask.resize((size, size), Image.Resampling.LANCZOS))
    return canvas


def comparison():
    REVIEW.mkdir(parents=True, exist_ok=True)
    canvas = Image.new("RGBA", (1080, 890), (17, 18, 22, 255))
    draw = ImageDraw.Draw(canvas)
    font_path = "/System/Library/Fonts/STHeiti Medium.ttc"
    title_font = ImageFont.truetype(font_path, 32)
    heading_font = ImageFont.truetype(font_path, 21)
    small_font = ImageFont.truetype(font_path, 17)
    draw.text((36, 24), "Moro · 原图像素处理 / 深色图标", font=title_font, fill="#f0eee9")
    draw.text((36, 76), "每组：浅色 Any  /  深色 Dark  /  60 px 小尺寸预览", font=small_font, fill="#b6b4c0")
    for i, (name, slug, title) in enumerate(ICONS):
        x, y = 32 + (i % 3) * 352, 124 + (i // 3) * 354
        draw.rounded_rectangle((x, y, x + 336, y + 334), radius=18,
                               fill="#1a1b21", outline="#35353d")
        draw.text((x + 20, y + 16), title, font=heading_font, fill="#f0eee9")
        folder = ASSETS / f"{name}.appiconset"
        original = Image.open(folder / f"appicon-{slug}-1024.png")
        dark = Image.open(folder / f"appicon-{slug}-dark-1024.png")
        canvas.alpha_composite(icon_tile(original, 136), (x + 20, y + 58))
        canvas.alpha_composite(icon_tile(dark, 136, True), (x + 178, y + 58))
        draw.text((x + 61, y + 204), "Any", font=small_font, fill="#b6b4c0")
        draw.text((x + 221, y + 204), "Dark", font=small_font, fill="#b6b4c0")
        canvas.alpha_composite(icon_tile(dark, 60, True), (x + 20, y + 250))
        draw.text((x + 98, y + 263), "60 px · 检查辨识度", font=small_font, fill="#b6b4c0")
    draw.text((36, 851), "底色与圆角为模拟，主屏幕实际效果由 iOS 渲染。", font=small_font, fill="#b6b4c0")
    canvas.convert("RGB").save(REVIEW / "comparison.png", optimize=True)


def main():
    for name, slug, _ in ICONS:
        folder = ASSETS / f"{name}.appiconset"
        # Always start geometry edits from the preserved source, never an output.
        source_path = (ORIGINALS if slug in ADJUSTED_SLUGS else folder) / f"appicon-{slug}-1024.png"
        source = Image.open(source_path).convert("RGB")
        assert source.size == (1024, 1024)
        any_image, image = prepare_icon(source, slug)
        if slug in ADJUSTED_SLUGS:
            any_image.save(folder / f"appicon-{slug}-1024.png", optimize=True)
        alpha = np.asarray(image)[..., 3] / 255
        assert 0.2 < (alpha == 0).mean() < 0.97, f"Unexpected matte: {name}"
        destination = folder / f"appicon-{slug}-dark-1024.png"
        image.save(destination, optimize=True)
        save_preview(name, slug, any_image, image)
        print(f"{name}: {destination.name}; transparent {(alpha == 0).mean():.1%}")
    comparison()


if __name__ == "__main__":
    main()
