#!/bin/bash
set -euo pipefail

source_dir="$(cd "$(dirname "$0")" && pwd)"
repo="$(git -C "$source_dir" rev-parse --show-toplevel)"
output="${MORO_FILM_OUTPUT:-$(dirname "$source_dir")}"
work="${MORO_FILM_WORK:-${TMPDIR:-/tmp}/moro-paper-current}"
mkdir -p "$work"
fps=30
frames=450
master="$repo/moro/Resources/Assets.xcassets/AppIcon.appiconset/appicon-default-1024.png"

prepare() {
    cp "$source_dir/Motion.metal" "$source_dir/folded-paper.png" "$work/"
    magick "$master" -fx 'min(1,max(0,(r-0.4*b)/0.6))' -colorspace gray "$work/head-mask.png"
    magick "$master" -fx 'min(1,max(0,(b-r)/0.6))' -colorspace gray "$work/ear-mask.png"
    magick "$master" -channel B -separate +channel -blur 0x9 "$work/shadow-mask.png"
    magick "$work/head-mask.png" "$work/ear-mask.png" "$work/shadow-mask.png" \
        -set colorspace sRGB -combine -depth 8 "PNG24:$work/ink.png"
    xcrun swiftc -O -module-cache-path "$work/modules" "$source_dir/Render.swift" -o "$work/render"
}

render() {
    local width="$1" height="$2" end="$3" start=0
    local ffinput=(-hide_banner -loglevel error -f rawvideo -pixel_format rgba -video_size "${width}x${height}" -framerate "$fps" -i -)
    if [[ "$end" == poster ]]; then
        start="${MORO_POSTER_FRAME:-0}"
        "$work/render" "$work" header "$width" "$height" "$frames" "$start" "$((start+1))" |
            ffmpeg -y "${ffinput[@]}" -frames:v 1 -update 1 "$work/header-$start.png"
    else
        mkdir -p "$output"
        staging=$(mktemp "$output/.header-XXXXXXXX")
        trap 'rm -f "$staging"' EXIT
        "$work/render" "$work" header "$width" "$height" "$frames" 0 "$frames" |
            ffmpeg -y "${ffinput[@]}" -an -vf 'scale=in_range=pc:out_color_matrix=bt709:out_range=tv,format=yuv420p' \
            -c:v libx264 -preset fast -crf 17 -threads 8 -g 60 -color_primaries bt709 -color_trc bt709 \
            -colorspace bt709 -movflags +faststart -f mp4 "$staging"
        mv "$staging" "$output/moro-header-v2-${width}x${height}.mp4"
    fi
}

case "${1:-header}" in
    prepare) prepare ;;
    poster)
        [[ "${2:-header}" == header ]] || { echo 'Use poster header WIDTH HEIGHT.' >&2; exit 2; }
        prepare
        render "${3:-3840}" "${4:-1646}" poster
        ;;
    header|all) prepare; render 3840 1646 film ;;
    *) echo 'Use header, prepare, or poster header WIDTH HEIGHT.' >&2; exit 2 ;;
esac
