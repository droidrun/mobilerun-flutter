# Shared helpers for the spike scripts (source me). No secrets in here.
# Requires ANDROID_HOME (cmdline-tools + emulator + platform-tools), JAVA_HOME (JDK 17) and flutter on PATH.
: ${ANDROID_HOME:?set ANDROID_HOME}; : ${JAVA_HOME:?set JAVA_HOME}
export ANDROID_SDK_ROOT=$ANDROID_HOME
export PATH=$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH
PKG=ai.mobilerun.spike.stream_spike
AVD=spike_a36
SERIAL=emulator-5580
ADB() { adb -s $SERIAL "$@"; }

emu_start() {
  if ! avdmanager list avd 2>/dev/null | grep -q "Name: $AVD"; then
    echo no | avdmanager create avd -n $AVD -k "system-images;android-36;google_apis;arm64-v8a" --force
  fi
  emulator -avd $AVD -port 5580 -no-window -no-audio -memory 2048 -no-snapshot -no-boot-anim -gpu swiftshader_indirect >"$OUT/emulator.log" 2>&1 &
  EMU_PID=$!
  local booted=0
  for i in $(seq 1 120); do
    [[ "$(ADB shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]] && { booted=1; break; }
    sleep 3
  done
  if [[ $booted != 1 ]]; then echo "emulator FAILED to boot"; tail -n 20 "$OUT/emulator.log"; return 1; fi
  echo "emulator booted pid=$EMU_PID"
}

emu_stop() {
  ADB emu kill >/dev/null 2>&1
  sleep 3
  pkill -f "qemu-system.*$AVD" 2>/dev/null
  pkill -f "emulator.*-avd $AVD" 2>/dev/null
  echo "emulator stopped"
}

# write_config <creds.json> <zpd true|false> <script name>: pipes the config
# into the app's private files dir; the token never touches argv or the repo.
write_config() {
  python3 -I - "$1" "$2" "$3" <<'PY' | ADB shell "run-as $PKG sh -c 'mkdir -p files && cat > files/spike.json'"
import json, sys
c = json.load(open(sys.argv[1]))
print(json.dumps({"deviceId": c["deviceId"], "streamUrl": c["streamUrl"], "streamToken": c["streamToken"],
                  "zpd": sys.argv[2] == "true", "script": sys.argv[3]}))
PY
}

shot() { ADB exec-out screencap -p > "$SHOTS/$1.png"; }

# logcat of the spike only; the app never prints the token or the WS URL.
launch() {
  ADB logcat -c
  ADB shell am force-stop $PKG
  ADB shell am start -n $PKG/.MainActivity >/dev/null
}
