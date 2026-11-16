#!/usr/bin/env bash
# Copyright 2026 Mobilerun
# SPDX-License-Identifier: Apache-2.0
# Credentials travel through stdin, never build defines or command arguments.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
creds="${1:?usage: tool/run-sample.sh CREDENTIALS_JSON [--ios]}"
[ -f "$creds" ] || { echo 'Credentials file not found' >&2; exit 2; }
creds="$(cd "$(dirname "$creds")" && pwd)/$(basename "$creds")"
platform="${2:-android}"
[ "$#" -le 2 ] && { [ "$platform" = android ] || [ "$platform" = --ios ]; } || {
  echo 'usage: tool/run-sample.sh CREDENTIALS_JSON [--ios]' >&2; exit 2;
}
command -v flutter >/dev/null || { echo 'Add Flutter to PATH first' >&2; exit 2; }
cd "$root/example"
flutter pub get
pkg=ai.mobilerun.mobilerun_flutter_example
pid=''
sim=''
container=''
adb_() { adb -s "emulator-$port" "$@"; }
cleanup() {
  if [ -n "$pid" ]; then
    adb_ shell run-as "$pkg" rm -f files/sample.json >/dev/null 2>&1 || true
    adb_ emu kill >/dev/null 2>&1 || true
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  if [ -n "$sim" ]; then
    [ -z "$container" ] || rm -f "$container/Library/Application Support/sample.json"
    xcrun simctl shutdown "$sim" >/dev/null 2>&1 || true
    xcrun simctl delete "$sim" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM
if [ "$platform" = --ios ]; then
  pkg=ai.mobilerun.mobilerunFlutterExample
  command -v xcrun >/dev/null || { echo 'Install Xcode and an iOS simulator runtime' >&2; exit 2; }
  flutter build ios --simulator --debug
  runtime="${SAMPLE_IOS_RUNTIME:-$(xcrun simctl list runtimes | sed -n '/^iOS .* - com.apple.CoreSimulator.SimRuntime.iOS-/s/.* - //p' | head -1)}"
  [ -n "$runtime" ] || { echo 'Install an iOS simulator runtime in Xcode first' >&2; exit 2; }
  sim="$(xcrun simctl create "Mobilerun sample $$" com.apple.CoreSimulator.SimDeviceType.iPhone-17 "$runtime")"
  xcrun simctl boot "$sim"
  xcrun simctl bootstatus "$sim" -b
  simulator_app="$(xcode-select -p)/Applications/Simulator.app"
  if [ -d "$simulator_app" ]; then open -a "$simulator_app"; fi
  xcrun simctl install "$sim" build/ios/iphonesimulator/Runner.app
  container="$(xcrun simctl get_app_container "$sim" "$pkg" data)"
  mkdir -p "$container/Library/Application Support"
  cat < "$creds" > "$container/Library/Application Support/sample.json"
  xcrun simctl launch "$sim" "$pkg" >/dev/null
  echo 'Sample launched. Press Ctrl-C to stop and delete its simulator.'
  while xcrun simctl list devices | grep -F "$sim" | grep -q Booted; do sleep 2; done
else
  : "${ANDROID_HOME:?set ANDROID_HOME to the Android SDK directory}"
  export PATH="$ANDROID_HOME/platform-tools:$PATH"
  emulator="$ANDROID_HOME/emulator/emulator"
  avd="${SAMPLE_AVD:-$("$emulator" -list-avds | sed -n '/^[A-Za-z0-9_.-][A-Za-z0-9_.-]*$/p' | head -1)}"
  [ -n "$avd" ] || { echo 'Create an Android API 35+ AVD in Android Studio first' >&2; exit 2; }
  port="${SAMPLE_EMULATOR_PORT:-5582}"
  [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 5554 ] && [ "$port" -le 5682 ] && [ "$((port % 2))" = 0 ] || {
    echo 'SAMPLE_EMULATOR_PORT must be an even port from 5554 to 5682' >&2; exit 2;
  }
  if adb devices | awk '{print $1}' | grep -qx "emulator-$port"; then
    echo 'Emulator port occupied; choose SAMPLE_EMULATOR_PORT' >&2; exit 2
  fi
  flutter build apk --debug
  log="${TMPDIR:-/tmp}/mobilerun-sample-emulator-$$.log"
  "$emulator" -avd "$avd" -port "$port" -no-snapshot -no-boot-anim > "$log" 2>&1 &
  pid=$!
  booted=0
  for ((i=0; i<180; i++)); do
    kill -0 "$pid" 2>/dev/null || { echo "Emulator stopped; see $log" >&2; exit 1; }
    if [ "$(adb_ shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; then
      booted=1; break
    fi
    sleep 1
  done
  [ "$booted" = 1 ] || { echo 'Emulator boot timed out' >&2; exit 1; }
  adb_ install -r build/app/outputs/flutter-apk/app-debug.apk
  adb_ shell am force-stop "$pkg"
  adb_ shell run-as "$pkg" mkdir -p files
  adb_ shell "run-as $pkg sh -c 'cat > files/sample.json'" < "$creds"
  adb_ shell am start -n "$pkg/.MainActivity" >/dev/null
  echo 'Sample launched. Press Ctrl-C to stop its emulator.'
  while kill -0 "$pid" 2>/dev/null; do sleep 2; done
fi
