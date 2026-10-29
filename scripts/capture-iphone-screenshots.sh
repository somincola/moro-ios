#!/bin/bash
# Captures the App Store showcase on a regular iPhone simulator (6.9", 1320 x 2868) through
# AppStoreShowcaseUITests, then exports the screenshots from the test results.
#
#   scripts/capture-iphone-screenshots.sh [locales] [pages]
#
#   locales  comma-separated, default "zh-Hans,en-US"
#   pages    comma-separated groups to (re)capture, default all (see AppStoreShowcaseUITests)
#
# Output: screenshots/app-store/<locale>/iphone/<page>.png, without an alpha channel
# (App Store screenshots can't carry one). Needs ImageMagick (`magick`).
#
# Environment: IPHONE_SIM overrides the simulator (an iPhone 17 Pro Max).
set -euo pipefail

LOCALES=${1:-"zh-Hans,en-US"}
PAGES=${2:-}
SIM=${IPHONE_SIM:-0EECE96B-E75A-41F4-85B4-284A7287518E}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d /tmp/moro-showcase.XXXXXX)
RESULT="$WORK/showcase.xcresult"
LOG="$WORK/xcodebuild.log"

command -v magick > /dev/null || { echo "needs ImageMagick (brew install imagemagick)" >&2; exit 1; }

xcrun simctl boot "$SIM" || true   # already booted is fine; bootstatus below fails if it can't boot
xcrun simctl bootstatus "$SIM" -b > /dev/null
xcrun simctl status_bar "$SIM" override --time 9:41 --batteryState charged --batteryLevel 100 \
    --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 --operatorName ""

echo "Testing on $SIM (log: $LOG)"
cd "$ROOT"
TEST_RUNNER_CAPTURE_STORE_SHOWCASE=1 TEST_RUNNER_SHOWCASE_LOCALES="$LOCALES" TEST_RUNNER_SHOWCASE_PAGES="$PAGES" \
    xcodebuild test -project moro.xcodeproj -scheme moro -destination "id=$SIM" \
    -derivedDataPath /tmp/moro-showcase-dd CODE_SIGNING_ALLOWED=NO -resultBundlePath "$RESULT" \
    -only-testing:moroUITests/AppStoreShowcaseUITests/testCaptureShowcase > "$LOG" 2>&1 &
PID=$!
# xcodebuild sometimes lingers after the tests finish without writing the result bundle;
# an interrupt makes it finish the bundle and exit.
until grep -qE "Test Suite 'Selected tests' (passed|failed)|BUILD FAILED" "$LOG"; do
    kill -0 "$PID" || break
    sleep 5
done
for _ in $(seq 1 12); do kill -0 "$PID" || break; sleep 5; done
kill -INT "$PID" || true
wait "$PID" || true
grep -E "Test Case .* (passed|failed)|error:|BUILD FAILED" "$LOG" | tail -5

xcrun simctl status_bar "$SIM" clear

xcrun xcresulttool export attachments --path "$RESULT" --output-path "$WORK/attachments" > /dev/null
python3 - "$WORK/attachments" "$ROOT/screenshots/app-store" <<'PYEOF'
import json, os, re, shutil, sys
source, destination = sys.argv[1], sys.argv[2]
manifest = json.load(open(os.path.join(source, "manifest.json")))
for test in manifest:
    for attachment in test["attachments"]:
        match = re.match(r"showcase__([^_]+)__(.+?)(_\d+_[0-9A-F-]+)?\.png$", attachment.get("suggestedHumanReadableName", ""))
        if not match:
            continue
        locale, page = match.group(1), match.group(2)
        folder = os.path.join(destination, locale, "iphone")
        os.makedirs(folder, exist_ok=True)
        target = os.path.join(folder, page + ".png")
        shutil.copy(os.path.join(source, attachment["exportedFileName"]), target)
        print("  " + target)
PYEOF
for file in "$ROOT"/screenshots/app-store/*/iphone/*.png; do
    magick "$file" -background white -alpha remove -alpha off "$file"
done
rm -rf "$WORK"
