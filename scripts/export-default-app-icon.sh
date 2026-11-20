#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
master=docs/design/brand/moro-default.svg
catalog=moro/Resources/Assets.xcassets
icons="$catalog/AppIcon.appiconset"
previews="$catalog/AppIconPreviewDefault.imageset"
primary="$icons/appicon-default-1024.png"
preview="$previews/appicon-preview-default.png"

# Supersample the curves. The black field belongs to the mark in both appearances.
magick -background black -density 384 "$master" -colorspace sRGB -filter Lanczos \
    -resize 1024x1024 -alpha off -depth 8 -strip -define png:exclude-chunk=time "PNG24:$primary"
magick "$primary" -filter Lanczos -resize 240x240 -strip -define png:exclude-chunk=time "PNG24:$preview"
cp "$primary" "$icons/appicon-default-dark-1024.png"
cp "$preview" "$previews/appicon-preview-default-dark.png"
cp "$primary" output/app-icons/default/icon-1024.png
