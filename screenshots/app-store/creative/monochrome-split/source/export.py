#!/usr/bin/env python3
"""Build & export Moro Monochrome Split (39%/61%) App Store Header & 10-locale Search films.

Specs:
- Product Page Header: 3840x1646 (21:9), 30 fps, 15.0s, H.264 Rec. 709 limited + AAC stereo 48 kHz 256 kbps
- Search Placement (10 storefronts): 3840x2560 (3:2), 30 fps, 12.0s, H.264 Rec. 709 limited + AAC stereo 48 kHz 256 kbps
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

SOURCE = Path(__file__).resolve().parent
CREATIVE = SOURCE.parent
APPSTORE = CREATIVE.parent.parent
REPO = APPSTORE.parent.parent

COPY_JSON = SOURCE / "copy.json"
SYNTH_SWIFT = SOURCE / "SynthBGM.swift"
RENDER_SWIFT = SOURCE / "Render.swift"
SVG_BRAND = REPO / "docs/design/brand/moro-default.svg"
ICON_1024 = REPO / "moro/Resources/Assets.xcassets/AppIcon.appiconset/appicon-default-1024.png"

WORK = Path("/tmp/moro-monochrome-split-work")
ASSETS_DIR = WORK / "assets"
AUDIO_DIR = WORK / "audio"
BIN_RENDER = WORK / "render"
BIN_SYNTH = WORK / "synth_bgm"

FPS = 30
TAGS = ["-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709", "-color_range", "tv"]
VIDEO_COLOR = (
    "scale=in_range=pc:out_color_matrix=bt709:out_range=tv,"
    "format=yuv444p10le,"
    "colorspace=iall=bt709:itrc=srgb:all=bt709:irange=tv:range=tv:format=yuv420p,"
    "setparams=range=limited:color_primaries=bt709:color_trc=bt709:colorspace=bt709"
)
H264_MASTER = [
    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-preset", "fast", "-crf", "16",
    "-g", "60", *TAGS,
    "-x264-params", "colorprim=bt709:transfer=bt709:colormatrix=bt709",
    "-bsf:v", "h264_metadata=colour_primaries=1:transfer_characteristics=1:matrix_coefficients=1:video_full_range_flag=0",
    "-movflags", "+faststart+write_colr",
]
H264_PREVIEW = [
    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-preset", "fast", "-crf", "20",
    "-g", "60", *TAGS, "-level:v", "4.0",
    "-x264-params", "colorprim=bt709:transfer=bt709:colormatrix=bt709",
    "-bsf:v", "h264_metadata=colour_primaries=1:transfer_characteristics=1:matrix_coefficients=1:video_full_range_flag=0",
    "-movflags", "+faststart+write_colr",
]
AUDIO_AAC = [
    "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2",
]
AUDIO_AAC_PREVIEW = [
    "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2",
]
FF = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y"]


def run(cmd):
    subprocess.run([str(c) for c in cmd], check=True)


def synth_audio(force=False, bgm="v12a"):
    WORK.mkdir(parents=True, exist_ok=True)
    mod_cache = WORK / "modules"
    mod_cache.mkdir(parents=True, exist_ok=True)
    if not BIN_SYNTH.exists() or SYNTH_SWIFT.stat().st_mtime_ns > BIN_SYNTH.stat().st_mtime_ns:
        print("Compiling acoustic melodic BGM synthesizer...", flush=True)
        run(["xcrun", "swiftc", "-O", "-module-cache-path", mod_cache, SYNTH_SWIFT, "-o", BIN_SYNTH])
    if force or not (AUDIO_DIR / "header-bgm-15s.wav").exists() or not (AUDIO_DIR / "search-bgm-12s.wav").exists():
        run([BIN_SYNTH, bgm, AUDIO_DIR])


def prepare_assets(bgm="v12a"):
    ASSETS_DIR.mkdir(parents=True, exist_ok=True)
    trans_png = ASSETS_DIR / "moro-mark-transparent.png"
    white_png = ASSETS_DIR / "moro-mark-white.png"
    if not trans_png.exists() or not white_png.exists():
        svg = SVG_BRAND.read_text()
        transparent = svg.replace('<rect width="1254" height="1254" fill="#000000"/>', "")
        white_only = transparent.replace('fill="#668CFF"', 'fill="#FFFFFF"')
        (ASSETS_DIR / "moro-transparent.svg").write_text(transparent)
        (ASSETS_DIR / "moro-white.svg").write_text(white_only)
        run(["magick", "-background", "none", "-density", "320", ASSETS_DIR / "moro-transparent.svg", "-resize", "1024x1024", trans_png])
        run(["magick", "-background", "none", "-density", "320", ASSETS_DIR / "moro-white.svg", "-resize", "1400x1400", white_png])

    synth_audio(force=False, bgm=bgm)


def remux_audio_all(locales, bgm="v12a"):
    """Fast lossless video-copy audio replacement across all 11 4K masters + web previews."""
    t0 = time.time()
    synth_audio(force=True, bgm=bgm)

    # 1. Header master + preview
    h_dir = CREATIVE / "header"
    h_master = h_dir / "moro-header-3840x1646.mp4"
    h_tmp = h_master.with_suffix(".audio.mp4")
    run([
        *FF, "-i", h_master, "-i", AUDIO_DIR / "header-bgm-15s.wav",
        "-map", "0:v:0", "-map", "1:a:0",
        "-c:v", "copy", *AUDIO_AAC,
        "-movflags", "+faststart+write_colr", "-shortest", h_tmp,
    ])
    os.replace(h_tmp, h_master)
    h_prev = h_dir / "header-preview.mp4"
    h_prev_tmp = h_prev.with_suffix(".audio.mp4")
    run([
        *FF, "-i", h_prev, "-i", h_master,
        "-map", "0:v:0", "-map", "1:a:0",
        "-c:v", "copy", "-c:a", "copy",
        "-movflags", "+faststart+write_colr", "-shortest", h_prev_tmp,
    ])
    os.replace(h_prev_tmp, h_prev)
    print("Remuxed Header master + preview", flush=True)

    # 2. All 10 Search masters + previews
    for loc in locales:
        s_dir = CREATIVE / "search" / loc
        s_master = s_dir / f"moro-search-{loc}-3840x2560.mp4"
        s_tmp = s_master.with_suffix(".audio.mp4")
        run([
            *FF, "-i", s_master, "-i", AUDIO_DIR / "search-bgm-12s.wav",
            "-map", "0:v:0", "-map", "1:a:0",
            "-c:v", "copy", *AUDIO_AAC,
            "-movflags", "+faststart+write_colr", "-shortest", s_tmp,
        ])
        os.replace(s_tmp, s_master)
        s_prev = s_dir / "preview.mp4"
        s_prev_tmp = s_prev.with_suffix(".audio.mp4")
        run([
            *FF, "-i", s_prev, "-i", s_master,
            "-map", "0:v:0", "-map", "1:a:0",
            "-c:v", "copy", "-c:a", "copy",
            "-movflags", "+faststart+write_colr", "-shortest", s_prev_tmp,
        ])
        os.replace(s_prev_tmp, s_prev)
        print(f"Remuxed Search [{loc}]", flush=True)
    print(f"All 11 masters + 11 previews remuxed in {time.time() - t0:.1f}s", flush=True)


def compile_renderer():
    WORK.mkdir(parents=True, exist_ok=True)
    mod_cache = WORK / "modules"
    mod_cache.mkdir(parents=True, exist_ok=True)
    if not BIN_RENDER.exists() or RENDER_SWIFT.stat().st_mtime_ns > BIN_RENDER.stat().st_mtime_ns:
        print("Compiling 4K Swift renderer...", flush=True)
        run([
            "xcrun", "swiftc", "-O",
            "-module-cache-path", mod_cache,
            "-framework", "AppKit",
            "-framework", "CoreGraphics",
            "-framework", "CoreText",
            RENDER_SWIFT, "-o", BIN_RENDER,
        ])


def pipe_encode(render_cmd, width, height, frames, audio_wav, out_mp4):
    out_mp4.parent.mkdir(parents=True, exist_ok=True)
    tmp_mp4 = out_mp4.with_suffix(".tmp.mp4")
    ff_cmd = [
        *FF,
        "-f", "rawvideo", "-pixel_format", "bgra",
        "-video_size", f"{width}x{height}", "-framerate", str(FPS),
        "-i", "pipe:0",
        "-i", str(audio_wav),
        "-map", "0:v:0", "-map", "1:a:0",
        "-vf", f"{VIDEO_COLOR},setsar=1",
        "-frames:v", str(frames),
        *H264_MASTER,
        *AUDIO_AAC,
        "-shortest",
        str(tmp_mp4),
    ]
    p_render = subprocess.Popen([str(c) for c in render_cmd], stdout=subprocess.PIPE)
    p_ff = subprocess.Popen(ff_cmd, stdin=p_render.stdout)
    p_render.stdout.close()
    rc_ff = p_ff.wait()
    rc_r = p_render.wait()
    if rc_r != 0 or rc_ff != 0:
        raise RuntimeError(f"Encode failed (render={rc_r}, ffmpeg={rc_ff}) for {out_mp4}")
    os.replace(tmp_mp4, out_mp4)


def export_header(proof_only=False):
    t0 = time.time()
    out_dir = CREATIVE / "header"
    out_dir.mkdir(parents=True, exist_ok=True)
    shots = APPSTORE / "en-US/iphone"
    kf_dir = WORK / "header-keyframes"
    kf_dir.mkdir(parents=True, exist_ok=True)

    run([BIN_RENDER, "header", ASSETS_DIR, shots, "keyframes", kf_dir])
    run(["magick", kf_dir / "frame-000.png", "-sampling-factor", "4:4:4", "-quality", "92", out_dir / "header-poster.jpg"])
    # Contact strip (0s, 3s, 6.5s, 10s) for quick inspection
    run([
        "magick",
        "(", kf_dir / "frame-000.png", kf_dir / "frame-090.png", "-resize", "960x412!", "-bordercolor", "#0A0B0E", "-border", "6", "+append", ")",
        "(", kf_dir / "frame-196.png", kf_dir / "frame-300.png", "-resize", "960x412!", "-bordercolor", "#0A0B0E", "-border", "6", "+append", ")",
        "-append", "-bordercolor", "#0A0B0E", "-border", "6",
        "-quality", "92",
        out_dir / "header-keyframes.jpg",
    ])

    if proof_only:
        print(f"Proofed Header keyframes in {time.time() - t0:.1f}s", flush=True)
        return

    master = out_dir / "moro-header-3840x1646.mp4"
    pipe_encode(
        [BIN_RENDER, "header", ASSETS_DIR, shots, "stream"],
        3840, 1646, 450,
        AUDIO_DIR / "header-bgm-15s.wav",
        master,
    )
    # Lightweight smooth web preview (1280x548 + AAC audio)
    preview = out_dir / "header-preview.mp4"
    run([
        *FF, "-i", master,
        "-vf", "scale=1280:548:flags=lanczos",
        *H264_PREVIEW, *AUDIO_AAC_PREVIEW,
        preview,
    ])
    print(f"Exported Header (3840x1646, 15s + BGM) in {time.time() - t0:.1f}s", flush=True)


def export_search_locale(locale, proof_only=False):
    t0 = time.time()
    native = "en-US" if locale == "ar-SA" else locale
    shots = APPSTORE / native / "iphone"
    out_dir = CREATIVE / "search" / locale
    out_dir.mkdir(parents=True, exist_ok=True)
    beats_dir = WORK / "search-beats" / locale
    beats_dir.mkdir(parents=True, exist_ok=True)

    run([BIN_RENDER, "search", COPY_JSON, locale, ASSETS_DIR, shots, ICON_1024, "beats", beats_dir])
    run(["magick", beats_dir / "beat-0.png", "-sampling-factor", "4:4:4", "-quality", "92", out_dir / "poster.jpg"])
    run([
        "magick",
        "(", beats_dir / "beat-0.png", beats_dir / "beat-1.png", "-resize", "960x640!", "-bordercolor", "#0E1014", "-border", "6", "+append", ")",
        "(", beats_dir / "beat-2.png", beats_dir / "beat-3.png", "-resize", "960x640!", "-bordercolor", "#0E1014", "-border", "6", "+append", ")",
        "-append", "-bordercolor", "#0E1014", "-border", "6",
        "-quality", "92",
        out_dir / "four-pages.jpg",
    ])

    if proof_only:
        print(f"Proofed Search [{locale}] beats in {time.time() - t0:.1f}s", flush=True)
        return

    master = out_dir / f"moro-search-{locale}-3840x2560.mp4"
    pipe_encode(
        [BIN_RENDER, "search", COPY_JSON, locale, ASSETS_DIR, shots, ICON_1024, "stream"],
        3840, 2560, 360,
        AUDIO_DIR / "search-bgm-12s.wav",
        master,
    )
    preview = out_dir / "preview.mp4"
    run([
        *FF, "-i", master,
        "-vf", "scale=960:640:flags=lanczos",
        *H264_PREVIEW, *AUDIO_AAC_PREVIEW,
        preview,
    ])
    print(f"Exported Search [{locale}] (3840x2560, 12s + BGM) in {time.time() - t0:.1f}s", flush=True)


def write_manifest(locales):
    manifest = {
        "concept": "Monochrome Split 39/61 (黑白双生)",
        "bpm": 80,
        "header": {
            "master": "header/moro-header-3840x1646.mp4",
            "preview": "header/header-preview.mp4",
            "poster": "header/header-poster.jpg",
            "keyframes": "header/header-keyframes.jpg",
            "width": 3840,
            "height": 1646,
            "fps": 30,
            "duration_s": 15.0,
        },
        "search": {
            loc: {
                "master": f"search/{loc}/moro-search-{loc}-3840x2560.mp4",
                "preview": f"search/{loc}/preview.mp4",
                "poster": f"search/{loc}/poster.jpg",
                "contact_sheet": f"search/{loc}/four-pages.jpg",
                "width": 3840,
                "height": 2560,
                "fps": 30,
                "duration_s": 12.0,
            }
            for loc in locales
        },
    }
    (CREATIVE / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--header", action="store_true", help="Export Product Page Header (3840x1646)")
    parser.add_argument("--search", action="store_true", help="Export Search Result Placements (3840x2560)")
    parser.add_argument("--locales", help="Comma-separated locales for Search (default: all 10)")
    parser.add_argument("--proof", action="store_true", help="Only render fast keyframes/beats & contact sheets (no MP4)")
    parser.add_argument("--remux-audio", action="store_true", help="Re-synthesize BGM and lossless-remux into all existing MP4s")
    parser.add_argument("--bgm", default="v12a", choices=["v12a", "v12b", "v11a", "v11b"], help="BGM finalist (v12a=Nostalgic v11A + Muffled Echo Accent, v12b=Nostalgic v11B + Muffled Echo Accent)")
    args = parser.parse_args()

    all_locales = list(json.loads(COPY_JSON.read_text()).keys())
    selected = args.locales.split(",") if args.locales else all_locales
    if not set(selected) <= set(all_locales):
        parser.error(f"Unknown locale(s): {set(selected) - set(all_locales)}")

    if args.remux_audio:
        remux_audio_all(selected, bgm=args.bgm)
        return

    do_header = args.header or (not args.header and not args.search)
    do_search = args.search or (not args.header and not args.search)

    prepare_assets(bgm=args.bgm)
    compile_renderer()

    if do_header:
        export_header(proof_only=args.proof)
    if do_search:
        for loc in selected:
            export_search_locale(loc, proof_only=args.proof)
    if not args.proof:
        write_manifest(all_locales)


if __name__ == "__main__":
    main()
