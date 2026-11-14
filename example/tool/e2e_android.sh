#!/usr/bin/env bash
# Copyright 2026 Mobilerun
# SPDX-License-Identifier: Apache-2.0
#
# Scripted run of the example app on an Android emulator against a cloud
# device: first frame, raw control bytes (HOME key, tap), forced signalling
# socket close and rebuild, mid-session credential refresh.
#
# Usage: example/tool/e2e_android.sh CREDENTIALS_JSON OUT_DIR
#
# CREDENTIALS_JSON holds {"streamUrl": "...", "streamToken": "..."}. It is
# piped into the app's private files directory with `adb run-as` and removed
# again; it never touches argv, the APK or the repository.
#
# Needs ANDROID_HOME (cmdline-tools, emulator, platform-tools, an arm64
# google_apis system image), a built debug APK (`flutter build apk --debug`
# in example/) and python3. Set AVD to use an existing virtual device.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 CREDENTIALS_JSON OUT_DIR" >&2
  exit 2
fi
creds="$1"
out="$2"
: "${ANDROID_HOME:?set ANDROID_HOME}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

here="$(cd "$(dirname "$0")/.." && pwd)"
apk="$here/build/app/outputs/flutter-apk/app-debug.apk"
pkg=ai.mobilerun.mobilerun_flutter_example
avd="${AVD:-mobilerun_e2e}"
port="${EMULATOR_PORT:-5582}"
serial="emulator-$port"
adb_() { adb -s "$serial" "$@"; }

mkdir -p "$out/shots"

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
status=timeout
seen=0
deadline=$((SECONDS + 600))
: >"$out/e2e.log"
while [ "$SECONDS" -lt "$deadline" ] && [ "$status" = timeout ]; do
  grep 'E2E ' "$out/logcat.raw" >"$out/e2e.tmp" || true
  total=$(wc -l <"$out/e2e.tmp" | tr -d ' ')
  while [ "$seen" -lt "$total" ]; do
    seen=$((seen + 1))
    line="$(sed -n "${seen}p" "$out/e2e.tmp")"
    msg="${line#*E2E }"
    echo "E2E $msg" | tee -a "$out/e2e.log"
    case "$msg" in
      "SHOT "*) adb_ exec-out screencap -p >"$out/shots/host-${msg#SHOT }.png" ;;
      DONE) status=done ;;
      FAILED*) status=failed ;;
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
