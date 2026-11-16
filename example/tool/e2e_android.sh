#!/usr/bin/env bash
# Copyright 2026 Mobilerun
# SPDX-License-Identifier: Apache-2.0
#
# Scripted run of the example app on an Android emulator against a cloud
# device: video pixels, widget touch/swipe, two fingers, rotated mapping,
# soft keyboard, system keys, hover, scroll, reconnect and ICE refresh.
#
# Usage: example/tool/e2e_android.sh CREDENTIALS_JSON OUT_DIR
#
# CREDENTIALS_JSON holds {"streamUrl": "...", "streamToken": "..."}. It is
# piped into the app's private files directory with `adb run-as` and removed
# again; it never touches argv, the APK or the repository.
#
# Needs ANDROID_HOME (cmdline-tools, emulator, platform-tools, an arm64
# google_apis system image), Flutter and python3. Builds the scripted target
# before installing it.
# Set AVD to use an existing virtual device.
#
# Proof of the picture is in pixels: every emulator screenshot of a live stream
# must show the device picture in the video area (tool/png_check.py), and the
# tap must change those pixels. The app asserts outgoing input frames too.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 CREDENTIALS_JSON OUT_DIR" >&2
  exit 2
fi
creds="$1"
out="$2"
: "${ANDROID_HOME:?set ANDROID_HOME}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:"\
"$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

here="$(cd "$(dirname "$0")/.." && pwd)"
apk="$here/build/app/outputs/flutter-apk/app-debug.apk"
pkg=ai.mobilerun.mobilerun_flutter_example
avd="${AVD:-mobilerun_e2e}"
port="${EMULATOR_PORT:-5582}"
serial="emulator-$port"
adb_() { adb -s "$serial" "$@"; }

mkdir -p "$out/shots"
(cd "$here" && flutter build apk --debug -t lib/e2e_main.dart)

if ! avdmanager list avd 2>/dev/null | grep -q "Name: $avd"; then
  echo no | avdmanager create avd -n "$avd" \
    -k "system-images;android-36;google_apis;arm64-v8a" --force
fi

cleanup() {
  adb_ shell "run-as $pkg rm -f files/e2e.json" >/dev/null 2>&1 || true
  adb_ emu kill >/dev/null 2>&1 || true
  sleep 3
  pkill -f "qemu-system.*$avd" 2>/dev/null || true
  echo "emulator stopped"
}
trap cleanup EXIT
emulator -avd "$avd" -port "$port" -no-window -no-audio -memory 2048 \
  -no-snapshot -no-boot-anim -gpu swiftshader_indirect \
  >"$out/emulator.log" 2>&1 &
booted=0
for _ in $(seq 1 120); do
  if [ "$(adb_ shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; then
    booted=1
    break
  fi
  sleep 3
done
[ "$booted" = 1 ] || { echo "emulator failed to boot" >&2; exit 1; }
echo "emulator booted"
adb_ install -r "$apk" >/dev/null
# One start creates the app's private directories.
adb_ shell am start -n "$pkg/.MainActivity" >/dev/null
sleep 3
adb_ shell am force-stop "$pkg"

python3 -I -c '
import json, sys
c = json.load(open(sys.argv[1]))
print(json.dumps({"streamUrl": c["streamUrl"], "streamToken": c["streamToken"]}))
' "$creds" | adb_ shell "run-as $pkg sh -c 'mkdir -p files && cat > files/e2e.json'"

adb_ shell "run-as $pkg rm -rf files/e2e-out"
adb_ logcat -c
adb_ shell am start -n "$pkg/.MainActivity" >/dev/null

# The app prints "E2E SHOT <name>" and waits two seconds: screenshot the
# emulator then. "E2E DONE" or "E2E FAILED" ends the run (ten minutes at most).
adb_ logcat -v brief -s flutter >"$out/logcat.raw" &
logcat_pid=$!
# Pixel checks of one emulator screenshot, see tool/png_check.py.
check_shot() {
  local png="$out/shots/host-$1.png" check="$here/tool/png_check.py"
  local before= min_lit=0.3
  # name | minimum lit fraction | baseline (empty means video-only check)
  while IFS='|' read -r name lit baseline; do
    if [ "$name" = "$1" ]; then
      min_lit="$lit"
      before="$baseline"
      break
    fi
  done <<'SHOTS'
03-after-tap|0.3|02-before-tap
05-after-swipe|0.3|04-before-swipe
07-rotated-home|0.08|
08-rotated-tap|0.08|07-rotated-home
09-recent|0.3|03-after-tap
12-final-home|0.3|11-platform-text
13-reconnecting|0|
16-reconnected-after-tap|0.3|15-reconnected-before-tap
SHOTS
  python3 -I "$check" "$png" --lit "$min_lit" | tee -a "$out/pixels.log" || return 1
  if [ -n "$before" ]; then
    python3 -I "$check" "$png" --differs-from "$out/shots/host-$before.png" 0.05 |
      tee -a "$out/pixels.log"
  fi
}

status=timeout
seen=0
deadline=$((SECONDS + 600))
: >"$out/e2e.log"
: >"$out/pixels.log"
while [ "$SECONDS" -lt "$deadline" ] && [ "$status" = timeout ]; do
  grep 'E2E ' "$out/logcat.raw" >"$out/e2e.tmp" || true
  total=$(wc -l <"$out/e2e.tmp" | tr -d ' ')
  while [ "$seen" -lt "$total" ]; do
    seen=$((seen + 1))
    line="$(sed -n "${seen}p" "$out/e2e.tmp")"
    msg="${line#*E2E }"
    echo "E2E $msg" | tee -a "$out/e2e.log"
    case "$msg" in
      "SHOT "*)
        name="${msg#SHOT }"
        adb_ exec-out screencap -p >"$out/shots/host-$name.png"
        if ! check_shot "$name"; then status=failed; fi
        ;;
      HOST-TYPE)
        # Tap three visible keys on the emulator's English soft keyboard.
        # Positions are fractions of the full screen, independent of density.
        size=$(adb_ shell wm size | tr -d '\r' |
          sed -n 's/.*: \([0-9]*\)x\([0-9]*\)/\1 \2/p' | tail -1)
        read -r sw sh <<<"$size"
        adb_ shell input tap "$((sw * 15 / 100))" "$((sh * 78 / 100))"
        adb_ shell input tap "$((sw * 25 / 100))" "$((sh * 78 / 100))"
        adb_ shell input tap "$((sw * 35 / 100))" "$((sh * 78 / 100))"
        ;;
      DONE) if [ "$status" = timeout ]; then status=done; fi ;;
      FAILED*)
        adb_ exec-out screencap -p >"$out/shots/host-failure.png"
        status=failed
        ;;
    esac
  done
  sleep 0.5
done
kill "$logcat_pid" 2>/dev/null || true
rm -f "$out/e2e.tmp" "$out/logcat.raw"

# Device screenshots taken by the app through session.screenshot().
for f in $(adb_ shell "run-as $pkg ls files/e2e-out" 2>/dev/null | tr -d '\r'); do
  adb_ exec-out "run-as $pkg cat files/e2e-out/$f" >"$out/shots/device-$f"
done
adb_ logcat -d -v brief -s flutter | sed 's/^.*flutter *: //' >"$out/app.log"
# Warnings and errors of every process, to diagnose native failures.
adb_ logcat -d -v brief '*:W' >"$out/native-warnings.log"
echo "run status: $status"
[ "$status" = done ]
