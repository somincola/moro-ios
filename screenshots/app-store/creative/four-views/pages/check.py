"""Check each storefront's native screenshots, static holds, branding, crop and loop."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
from html.parser import HTMLParser
import json
import re
import subprocess

from export import COPY, EXPORTS, FILM, FPS, FRAMES, SAFE, STILL_COLOR, STORE, SWATCH_Y

NATIVE = ["home-light.png", "inbox.png", "profile.png", "display.png"]
W, H = 424, 202
HOLD_FRAMES = (30, 120, 210, 300)
CUT_FRAMES = [75, 165, 255, 345]
TEST_FRAMES = (0, *HOLD_FRAMES, FRAMES - 1)


def output(args):
    return subprocess.check_output(list(map(str, args)))


def require(condition, detail):
    if not condition:
        raise ValueError(detail)


def probe(path, dimensions, frame_count):
    meta = json.loads(output(["ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", path]))
    streams = meta["streams"]
    wanted = dict(codec_type="video", codec_name="h264", width=dimensions[0], height=dimensions[1],
                  pix_fmt="yuv420p", color_range="tv", color_space="bt709", color_transfer="bt709",
                  color_primaries="bt709", r_frame_rate="30/1", nb_frames=str(frame_count))
    require(len(streams) == 1 and all(streams[0].get(k) == v for k, v in wanted.items()), f"Stream mismatch: {path}")
    require(float(meta["format"]["duration"]) == frame_count / FPS and path.stat().st_size <= 524_288_000, str(path))


def samples(movie, crop, indices, *, display_filter=None):
    select = "+".join(f"eq(n,{n})" for n in indices)
    filters = [f"select='{select}'"]
    if crop:
        x, y, w, h = crop
        filters.append(f"crop={w}:{h}:{x}:{y}:exact=1")
    if display_filter:
        filters.append(display_filter)
    filters += [f"scale={W}:{H}:flags=area", "format=rgb24"]
    raw = output(["ffmpeg", "-v", "error", "-xerror", "-threads", "3", "-i", movie, "-vf", ",".join(filters),
                  "-fps_mode", "passthrough", "-threads", "1", "-c:v", "rawvideo", "-f", "rawvideo", "-"])
    stride = W * H * 3
    require(len(raw) == len(indices) * stride, f"Could not decode all holds: {movie}")
    return [raw[i:i + stride] for i in range(0, len(raw), stride)]


def crop_pixels(frame, left, top, width, height):
    return b"".join(frame[3 * (y * W + left):3 * (y * W + left + width)] for y in range(top, top + height))


def mean_error(first, second):
    require(len(first) == len(second) and len(first) > 0, "Mismatched comparison")
    return sum(abs(a - b) for a, b in zip(first, second)) / len(first)


def design_box(left, top, right, bottom):
    x, y, w, h = SAFE
    def convert(i, start, length, canvas):
        return round((i * 3840 / 1500 - start) * canvas / length)
    l, r = (convert(v, x, w, W) for v in (left, right))
    t, b = (convert(v, y, h, H) for v in (top, bottom))
    return l, t, r - l, b - t


def check_native_pages(locale, native, frames):
    # Mid-hold crops are calculated against the original 1320 × 2868 screenshots, independently
    # of the renderer. Ignore only the rounded edge and compare text, photos and native tint together.
    box = design_box(711, 340, 1129, 660)
    left, top, width, height = box
    safe_x, safe_y, safe_w, safe_h = SAFE
    design_x = (safe_x + left * safe_w / W) / 2.56
    design_y = (safe_y + top * safe_h / H) / 2.56
    page_tops = [311, 183, 289, SWATCH_Y[native] - 693]
    errors = []
    for i, (frame, filename) in enumerate(zip(frames, NATIVE)):
        native_width = 1260 if i == 3 else 1320
        factor = native_width / 448
        sx = round((30 if i == 3 else 0) + (design_x - 696) * factor)
        sy = round(page_tops[i] + (design_y - 326) * factor)
        sw = round(width * safe_w / W / 2.56 * factor)
        sh = round(height * safe_h / H / 2.56 * factor)
        ref = output(["magick", STORE / native / "iphone" / filename, "-crop", f"{sw}x{sh}+{sx}+{sy}", "+repage",
                      "-colorspace", "sRGB", "-filter", "Box", "-resize", f"{width}x{height}!", "-depth", "8", "rgb:-"])
        error = mean_error(crop_pixels(frame, *box), ref)
        require(error < 9, f"{locale} {filename}: native screenshot comparison {error:.2f}")
        errors.append(round(error, 2))
    return errors


class ReviewPage(HTMLParser):
    def __init__(self):
        super().__init__()
        self.locales, self.beats = [], []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "option":
            self.locales.append(attrs["value"])
        if "data-at" in attrs:
            self.beats.append(round(float(attrs["data-at"]) * FPS))
        for key in ("href", "src", "poster"):
            if key in attrs:
                require((FILM / attrs[key]).is_file(), f"Broken review link: {attrs[key]}")


def check_cuts(movie):
    x, y, w, h = SAFE
    filters = (f"crop={w}:{h}:{x}:{y}:exact=1,scale=424:202:flags=area,format=yuv420p,"
               "tblend=all_mode=difference,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-")
    stats = output(["ffmpeg", "-v", "error", "-xerror", "-threads", "3", "-i", movie, "-vf", filters, "-an",
                    "-f", "null", "-"]).decode()
    entries = re.findall(r"pts_time:([\d.]+)\s+lavfi.signalstats.YAVG=([\d.eE+-]+)", stats)
    changes = {round(float(t) * FPS): float(change) for t, change in entries}
    require(len(changes) == FRAMES - 1, f"Missing frame differences: {movie}")
    require([n for n, change in changes.items() if change > 3] == CUT_FRAMES, f"Unexpected page cuts: {movie}")
    require(max(change for n, change in changes.items() if n not in CUT_FRAMES) < 0.7, f"Movement within a page: {movie}")


def region(frame, coordinates):
    return crop_pixels(frame, *design_box(*coordinates))


def ink_pixels(data):
    return sum(max(rgb) < 166 for rgb in zip(data[::3], data[1::3], data[2::3]))


def check_brand(locale, frames):
    logos = [region(frame, (369, 389, 421, 441)) for frame in frames]
    signatures = [region(frame, (366, 623, 605, 672)) for frame in frames]
    colors = list(zip(logos[0][::3], logos[0][1::3], logos[0][2::3]))
    require(sum(max(c) < 46 for c in colors) > 160 and sum(min(c) > 220 for c in colors) > 35
            and sum(b > r + 52 and b > g + 28 for r, g, b in colors) > 3, f"{locale}: missing official black, white and blue mark")
    require(ink_pixels(signatures[0]) > 160, f"{locale}: missing lower-left wordmark")
    for logo, signature in zip(logos[1:], signatures[1:]):
        require(mean_error(logos[0], logo) < 2 and mean_error(signatures[0], signature) < 2,
                f"{locale}: brand moves between pages")
    for frame in frames:
        for box in [(428, 385, 665, 438), (366, 451, 665, 502), (366, 505, 665, 560)]:
            require(ink_pixels(region(frame, box)) >= 22, f"{locale}: missing page name or copy")
        require(min(region(frame, (669, 382, 684, 665))) > 175, f"{locale}: content crosses the gutter")


def check_locale(locale):
    path = EXPORTS / locale
    movie = path / f"moro-search-{locale}-3840x2560.mp4"
    native = "en-US" if locale == "ar-SA" else locale
    probe(movie, (3840, 2560), FRAMES)
    check_cuts(movie)
    frames = samples(movie, SAFE, TEST_FRAMES, display_filter=STILL_COLOR)
    errors = check_native_pages(locale, native, frames[1:-1])
    require(mean_error(frames[0], frames[1]) < 1 and mean_error(frames[0], frames[-1]) < 1,
            f"{locale}: the film must start and finish on Home")
    check_brand(locale, frames)
    poster = path / "poster.jpg"
    require(output(["magick", "identify", "-format", "%wx%h", poster]) == b"3840x2560", str(poster))
    require(mean_error(frames[0], samples(poster, SAFE, (0,))[0]) < 2.5, f"{locale}: poster differs from Home")
    sheet = path / "four-pages.jpg"
    require(output(["magick", "identify", "-format", "%wx%h", sheet]) == b"1572x766", f"{locale}: invalid four-page sheet")
    for index, frame in enumerate(frames[1:-1]):
        x, y = 12 + (index % 2) * 780, 12 + (index // 2) * 377
        tile = output(["magick", sheet, "-crop", f"768x365+{x}+{y}", "+repage", "-filter", "Box",
                       "-resize", f"{W}x{H}!", "-depth", "8", "rgb:-"])
        require(mean_error(frame, tile) < 4, f"{locale}: static page {index + 1} differs from the film")
    proxy = path / "preview.mp4"
    probe(proxy, (960, 640), FRAMES)
    require(max(map(mean_error, frames, samples(proxy, (209, 191, 542, 258), TEST_FRAMES, display_filter=STILL_COLOR))) < 6,
            f"{locale}: proxy differs from master")
    if locale == "zh-Hans":
        card = path / "search-card.mp4"
        probe(card, (1084, 516), FRAMES)
        require(max(map(mean_error, frames, samples(card, None, TEST_FRAMES, display_filter=STILL_COLOR))) < 4, "Incorrect card crop")
    print(f"{locale}: {FRAMES} frames, four static views, correct brand and cut points", flush=True)
    return {"locale": locale, "appInterfaceLocale": native, "file": str(movie.relative_to(EXPORTS)),
            "sha256": hashlib.sha256(movie.read_bytes()).hexdigest(), "bytes": movie.stat().st_size,
            "nativePageMeanAbsoluteErrorRGB8": errors}


if __name__ == "__main__":
    locales = list(json.loads(COPY.read_text()))
    review = ReviewPage()
    review.feed((FILM / "review.html").read_text())
    require(set(review.locales) == set(locales) and review.beats == list(HOLD_FRAMES), "Review locales or cues differ")
    with ThreadPoolExecutor(max_workers=2) as pool:
        assets = list(pool.map(check_locale, locales))
    manifest = {"placement": "searchResult", "width": 3840, "height": 2560, "framesPerSecond": FPS,
                "durationSeconds": FRAMES / FPS, "audio": False, "safeArea": list(SAFE), "cutFrames": CUT_FRAMES,
                "assets": assets}
    (EXPORTS / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
