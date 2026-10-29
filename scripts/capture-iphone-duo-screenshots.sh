#!/bin/bash
# Captures the App Store showcase on the iPhone Duo simulator, in the pose it is in now.
#
#   scripts/capture-iphone-duo-screenshots.sh <pose> [locales]
#
#   pose     inner-portrait | inner-landscape | outer-portrait | outer-landscape
#            (set it first in Device Hub; "outer" means closed)
#   locales  space-separated, default "zh-Hans en-US"
#
# Install a Debug build on the simulator first (the showcase harness is Debug-only).
# Screens are read per display with simctl: while the Duo is open, XCUITest screenshots
# capture the outer display, which is off. Output goes to
# screenshots/app-store/<locale>/iphone-duo/<pose>/NN-<page>.png at the display's native size
# (inner 2007 x 2853, outer 1398 x 2034, or rotated).
#
# App Store screenshots can't carry an alpha channel: ImageMagick (`magick`) flattens them.
#
# DUO_PAGES limits the run to some pages by file stem, e.g. DUO_PAGES="07-onboarding".
#
# Environment: DUO_SIM, DUO_INNER_DISPLAY, DUO_OUTER_DISPLAY override the simulator and
# display identifiers (see `xcrun simctl list devices` and Device Hub).
set -euo pipefail

POSE=${1:?pose: inner-portrait | inner-landscape | outer-portrait | outer-landscape}
LOCALES=${2:-"zh-Hans en-US"}
SIM=${DUO_SIM:-6C305F2A-89BB-4117-8992-0D7B3947A197}
INNER=${DUO_INNER_DISPLAY:-817DDF04-73E7-41EF-8196-5D89C08BA3C3}
OUTER=${DUO_OUTER_DISPLAY:-D851A9BC-FBB2-48B1-9C54-9B7EC7CBA3DA}
BUNDLE=com.somincola.moro
ROOT=$(cd "$(dirname "$0")/.." && pwd)

command -v magick > /dev/null || { echo "needs ImageMagick (brew install imagemagick)" >&2; exit 1; }

case "$POSE" in
    inner-*) DISPLAY_ID=$INNER ;;
    outer-*) DISPLAY_ID=$OUTER ;;
    *) echo "unknown pose: $POSE" >&2; exit 1 ;;
esac

xcrun simctl status_bar "$SIM" override --time 9:41 --batteryState charged --batteryLevel 100 \
    --wifiMode active --wifiBars 3 --cellularMode notSupported

# capture <file stem> <seconds to settle> [VAR=value ...] -- [launch arguments ...]
capture() {
    local stem=$1 settle=$2; shift 2
    if [ -n "${DUO_PAGES:-}" ] && [[ " $DUO_PAGES " != *" $stem "* ]]; then return; fi
    local env_args=() launch_args=()
    # UITEST_USE_FULL_APP lets the launch environment set the color scheme.
    env_args+=("SIMCTL_CHILD_UITEST_USE_FULL_APP=1")
    while [ $# -gt 0 ] && [ "$1" != "--" ]; do env_args+=("SIMCTL_CHILD_$1"); shift; done
    [ "${1:-}" = "--" ] && shift
    launch_args=("$@")
    env "${env_args[@]}" xcrun simctl launch --terminate-running-process "$SIM" "$BUNDLE" \
        "${launch_args[@]}" "${LOCALE_ARGS[@]}" > /dev/null
    # The showcase has no readiness signal: give it a fixed moment to load and lay out.
    sleep "$settle"
    xcrun simctl io "$SIM" screenshot --display="$DISPLAY_ID" --mask=ignored "$OUT/$stem.png" > /dev/null
    magick "$OUT/$stem.png" -background white -alpha remove -alpha off "$OUT/$stem.png"
    echo "  $OUT/$stem.png"
}

for LOCALE in $LOCALES; do
    LOCALE_ARGS=(-AppleLanguages "($LOCALE)" -AppleLocale "${LOCALE//-/_}")
    OUT="$ROOT/screenshots/app-store/$LOCALE/iphone-duo/$POSE"
    mkdir -p "$OUT"
    echo "$LOCALE, $POSE:"
    STORE=(-APP_STORE_SCREENSHOTS APP_STORE_SCREENSHOTS)

    if [ "$POSE" = inner-landscape ]; then
        # The wide display's two columns, each with a thread open.
        capture 01-home-thread 10 STORE_SHOWCASE=1 STORE_THREAD=0 UITEST_COLOR_SCHEME=light -- "${STORE[@]}"
        capture 02-home-thread-dark 10 STORE_SHOWCASE=1 STORE_THREAD=0 UITEST_COLOR_SCHEME=dark -- "${STORE[@]}"
        capture 03-inbox-thread 10 STORE_SHOWCASE=1 STORE_TAB=inbox STORE_THREAD=1 UITEST_COLOR_SCHEME=light -- "${STORE[@]}"
    else
        capture 01-home 8 STORE_SHOWCASE=1 UITEST_COLOR_SCHEME=light -- "${STORE[@]}"
        capture 02-home-dark 8 STORE_SHOWCASE=1 UITEST_COLOR_SCHEME=dark -- "${STORE[@]}"
        capture 03-thread 10 STORE_SHOWCASE=1 STORE_THREAD=0 UITEST_COLOR_SCHEME=light -- "${STORE[@]}"
        capture 04-inbox 8 STORE_SHOWCASE=1 STORE_TAB=inbox UITEST_COLOR_SCHEME=light -- "${STORE[@]}"
    fi
    capture 05-profile 8 STORE_SHOWCASE=1 STORE_TAB=me UITEST_COLOR_SCHEME=light -- "${STORE[@]}"
    capture 06-display 7 STORE_SHOWCASE=1 STORE_SCENE=display STORE_THEME_COLOR=purple UITEST_COLOR_SCHEME=light -- "${STORE[@]}"
    # The gathered globe with the title and button, not the opening net.
    capture 07-onboarding 9 UITEST_ONBOARDING_VARIANT=globe UITEST_ONBOARDING_GATHER=1 UITEST_COLOR_SCHEME=dark -- UITEST_ONBOARDING_PREVIEW
done

xcrun simctl status_bar "$SIM" clear
