"""Export four still pages with direct cuts for the App Store search placement."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import subprocess
import tempfile

PAGES = Path(__file__).resolve().parent
FILM = PAGES.parent
STORE = FILM.parent.parent
COPY = FILM / "source/copy.json"
# Source screenshot rows move with localized text wrapping.
SWATCH_Y = {"zh-Hans": 2205, "zh-Hant": 2285, "en-US": 2373, "de-DE": 2421, "fr-FR": 2421,
            "es-ES": 2333, "it": 2333, "ja": 2333, "pt-PT": 2333}
FPS = 30
SAFE = (836, 765, 2168, 1030)
TAGS = ["-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709", "-color_range", "tv"]
COLOR_FILTER = "scale=in_range=pc:out_color_matrix=bt709:out_range=tv"
H264 = ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-preset", "veryfast", "-crf", "16", "-threads", "5",
        "-g", "60", *TAGS, "-x264-params", "colorprim=bt709:transfer=bt709:colormatrix=bt709",
        "-bsf:v", "h264_metadata=colour_primaries=1:transfer_characteristics=1:matrix_coefficients=1:video_full_range_flag=0",
        "-movflags", "+faststart+write_colr"]
FF = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-nostdin"]


EXPORTS = PAGES / "exports"
ICON = STORE.parents[1] / "output/app-icons/default/icon-1024.png"
# The home page's three-second hold straddles the loop. The first and last frames match.
EDIT = [(0, 75), (1, 90), (2, 90), (3, 90), (0, 15)]
FRAMES = sum(count for _, count in EDIT)
# The Apple bitmap carries an sRGB ICC profile. Convert the transfer curve, then remove the
# source ICC side data so the muxer cannot mark Rec. 709 video as an sRGB still image.
VIDEO_COLOR = (COLOR_FILTER + ",format=yuv444p10le,"
               "colorspace=iall=bt709:itrc=srgb:all=bt709:irange=tv:range=tv:format=yuv420p,"
               "sidedata=mode=delete:type=ICC_PROFILE,"
               "setparams=range=limited:color_primaries=bt709:color_trc=bt709:colorspace=bt709")
STILL_COLOR = "colorspace=iall=bt709:all=bt709:trc=srgb:irange=tv:range=tv:format=yuv444p"


def run(args):
    return subprocess.run(list(map(str, args)), check=True)


def review_files(movie, directory, chinese, *, poster_source):
    run(["magick", poster_source, "-sampling-factor", "4:4:4", "-quality", "92", directory / "poster.jpg"])
    sizes = [("scale=960:640:flags=lanczos", "preview.mp4")]
    if chinese:
        x, y, w, h = SAFE
        sizes.append((f"crop=w={w}:h={h}:x={x}:y={y}:exact=1,scale=1084:516:flags=lanczos", "search-card.mp4"))
    for filt, name in sizes:
        run(FF + ["-threads", "3", "-i", movie, "-vf", filt, "-an", *H264, "-level:v", "3.1", directory / name])


def contact_sheet(movie, destination):
    # All four panels are decoded from the final safe-area crop, at the same holds as the review buttons.
    marks = "select='eq(n,30)+eq(n,120)+eq(n,210)+eq(n,300)'"
    x, y, w, h = SAFE
    filters = (f"{marks},crop={w}:{h}:{x}:{y}:exact=1,{STILL_COLOR},scale=768:365:flags=lanczos,"
               "setsar=1,tile=2x2:padding=12:margin=12:color=white")
    run(FF + ["-threads", "3", "-i", movie, "-vf", filters, "-frames:v", "1", "-update", "1",
              "-q:v", "2", destination])


def build(work):
    for src, name in [(PAGES.parent / "source/Captions.swift", "captions"), (PAGES / "Cards.swift", "cards")]:
        binary = work / name
        if not binary.exists() or src.stat().st_mtime_ns > binary.stat().st_mtime_ns:
            run(["xcrun", "swiftc", "-O", "-module-cache-path", work / "modules", src, "-o", binary])


def export(locale, work, proof):
    native = "en-US" if locale == "ar-SA" else locale
    shots = work / locale
    shots.mkdir(exist_ok=True)
    atlas = shots / "captions.png"
    run([work / "captions", COPY, locale, atlas])
    run([work / "cards", STORE / native / "iphone", atlas, ICON, shots, SWATCH_Y[native]])
    if proof:
        return
    sequence = ["ffconcat version 1.0"]
    cut_frames = []
    cursor = 0
    for page, length in EDIT:
        cut_frames.append(cursor)
        sequence.extend([f"file page-{page}.png", f"option framerate {FPS}", f"duration {length / FPS:.6f}"])
        cursor += length
    # Give the concat demuxer the end timestamp of the final hold.
    sequence.extend([f"file page-{EDIT[-1][0]}.png", f"option framerate {FPS}"])
    playlist = shots / "pages.ffconcat"
    playlist.write_text("\n".join(sequence) + "\n")
    output = EXPORTS / locale
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output) as tmpdir:
        tmp = Path(tmpdir)
        movie = tmp / f"moro-search-{locale}-3840x2560.mp4"
        cuts = ",".join(f"{n / FPS:g}" for n in cut_frames)
        run(FF + ["-f", "concat", "-safe", "0", "-i", playlist, "-vf",
                  f"{VIDEO_COLOR},setsar=1,fps={FPS}", "-frames:v", FRAMES, "-an",
                  *H264, "-g", FRAMES, "-sc_threshold", "0", "-force_key_frames", cuts, movie])
        review_files(movie, tmp, locale == "zh-Hans", poster_source=shots / "page-0.png")
        contact_sheet(movie, tmp / "four-pages.jpg")
        for artifact in tmp.iterdir():
            os.replace(artifact, output / artifact.name)
    print("Exported", locale, flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, default=Path(tempfile.gettempdir()) / "moro-page-showcase")
    parser.add_argument("--locales", help="Comma-separated storefronts (default: all)")
    parser.add_argument("--proof", action="store_true", help="Typeset the four full-resolution stills only")
    parser.add_argument("--jobs", type=int, default=2)
    args = parser.parse_args()
    locales = list(json.loads(COPY.read_text()))
    selected = args.locales.split(",") if args.locales else locales
    if not set(selected) <= set(locales) or args.jobs < 1:
        parser.error("Invalid locale or worker count")
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    build(work)
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        list(pool.map(lambda locale: export(locale, work, args.proof), selected))
