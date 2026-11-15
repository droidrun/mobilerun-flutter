#!/usr/bin/env bash
# Copyright 2026 Mobilerun
# SPDX-License-Identifier: Apache-2.0
# Use exclusive emulator access. Credentials never enter argv or the APK.
# Usage: tool/benchmark.sh CREDENTIALS_JSON OUT_DIR
set -euo pipefail
[ "$#" = 2 ] || { echo 'usage: tool/benchmark.sh CREDENTIALS_JSON OUT_DIR' >&2; exit 2; }
creds="$1"
out="$2"
root="$(cd "$(dirname "$0")/.." && pwd)"
: "${ANDROID_HOME:?set ANDROID_HOME}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
pkg=ai.mobilerun.mobilerun_flutter_example
avd="${AVD:-mobilerun_benchmark}"
port="${EMULATOR_PORT:-5584}"
serial="emulator-$port"
adb_() { adb -s "$serial" "$@"; }
mkdir -p "$out/shots"
: >"$out/benchmark.log"
cleanup() {
  if [ -n "${logger:-}" ]; then kill "$logger" 2>/dev/null || true; fi
  adb_ shell "run-as $pkg rm -f files/e2e.json files/benchmark-ack" >/dev/null 2>&1 || true
  adb_ emu kill >/dev/null 2>&1 || true
  if [ -n "${emulator_pid:-}" ]; then wait "$emulator_pid" 2>/dev/null || true; fi
  echo 'emulator stopped'
}
trap cleanup EXIT INT TERM
(cd "$root/example" && flutter build apk --debug -t lib/benchmark_main.dart) >"$out/build.log" 2>&1 || {
  tail -30 "$out/build.log"; exit 1;
}
emulator -avd "$avd" -port "$port" -no-window -no-audio -memory 2048 \
  -no-snapshot -no-boot-anim -gpu swiftshader_indirect >"$out/emulator.log" 2>&1 &
emulator_pid=$!
booted=0
for _ in $(seq 1 120); do
  if [ "$(adb_ shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; then booted=1; break; fi
  sleep 3
done
[ "$booted" = 1 ] || { echo 'emulator failed to boot'; exit 1; }
# Keep the foreground soak visible; automatic screen sleep is tested separately
# by the explicit background/foreground cycle.
adb_ shell settings put system screen_off_timeout 1800000
adb_ shell wm size 1080x2400
adb_ shell wm density 440
adb_ install -r "$root/example/build/app/outputs/flutter-apk/app-debug.apk" >/dev/null
# Establish the private directory without credentials, then restart with them.
adb_ shell am start -n "$pkg/.MainActivity" >/dev/null
sleep 2
adb_ shell am force-stop "$pkg"
python3 -I -c 'import json,sys; c=json.load(open(sys.argv[1])); print(json.dumps({"streamUrl":c["streamUrl"],"streamToken":c["streamToken"]}))' "$creds" |
  adb_ shell "run-as $pkg sh -c 'mkdir -p files && cat > files/e2e.json'"
adb_ shell "run-as $pkg rm -f files/benchmark-results.md files/hardening-results.md files/benchmark-ack"
adb_ logcat -c
adb_ logcat -v raw -s flutter:I '*:S' >"$out/app.log" &
logger=$!
adb_ shell am start -n "$pkg/.MainActivity" >/dev/null
seen=0
status=timeout
deadline=$((SECONDS + 1800))
while [ "$SECONDS" -lt "$deadline" ] && [ "$status" = timeout ]; do
  # Print only harness-authored diagnostic lines, never transport exceptions.
  sed -n 's/.*BENCH /BENCH /p' "$out/app.log" >"$out/messages.tmp"
  count=$(wc -l <"$out/messages.tmp" | tr -d ' ')
  while [ "$seen" -lt "$count" ]; do
    seen=$((seen + 1))
    message=$(sed -n "${seen}p" "$out/messages.tmp")
    echo "$message" | tee -a "$out/benchmark.log"
    case "$message" in
      'BENCH HOST '*)
        action="${message#BENCH HOST }"
        case "$action" in
          'shot '*) adb_ exec-out screencap -p >"$out/shots/${action#shot }.png" ;;
          tablet) adb_ shell wm size 1600x2560; adb_ shell wm density 240; sleep 3 ;;
          phone) adb_ shell wm size 1080x2400; adb_ shell wm density 440; sleep 3 ;;
          background)
            adb_ shell input keyevent KEYCODE_HOME; sleep 5
            adb_ shell am start -n "$pkg/.MainActivity" >/dev/null; sleep 3 ;;
          network)
            adb_ shell svc wifi disable; adb_ shell svc data disable; sleep 15
            adb_ shell svc wifi enable; adb_ shell svc data enable; sleep 5 ;;
          soak-start|soak-end) adb_ shell dumpsys meminfo "$pkg" >"$out/$action-memory.txt" ;;
        esac
        adb_ shell "run-as $pkg touch files/benchmark-ack"
        ;;
      'BENCH FAILED '*) status=failed ;;
      'BENCH DONE') status=done ;;
    esac
  done
  sleep .2
done
for name in benchmark-results.md hardening-results.md; do
  if adb_ exec-out "run-as $pkg cat files/$name" >"$out/$name.tmp" 2>/dev/null; then
    mv "$out/$name.tmp" "$out/$name"
  else
    rm -f "$out/$name.tmp" "$out/$name"
  fi
done
if [ ! -s "$out/benchmark-results.md" ]; then
  printf '# Stream benchmark\n\nNo complete run recorded. Runtime status: %s. See benchmark.log.\n' "$status" >"$out/benchmark-results.md"
fi
rm -f "$out/messages.tmp"
echo "benchmark status: $status"
[ "$status" = done ]
