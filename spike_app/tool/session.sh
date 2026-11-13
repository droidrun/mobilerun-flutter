#!/bin/zsh
# Full measurement session in ONE emulator boot. Usage: session.sh CREDS_JSON OUT_DIR
# Coordinates are for a 1080x2400 emulator: Settings icon on the cloud home screen,
# and the four buttons under the video (Connect, KillWS, Refresh, Stats).
source "$(dirname "$0")/lib.sh"
CREDS=$1; OUT=$2; SHOTS=$OUT/shots; mkdir -p $OUT $SHOTS
trap emu_stop EXIT
emu_start || exit 1
ADB install -r build/app/outputs/flutter-apk/app-debug.apk
ADB shell am start -n $PKG/.MainActivity >/dev/null; sleep 3; ADB shell am force-stop $PKG
grab() { ADB logcat -d -s flutter | sed 's/^.*flutter *: //' > "$OUT/$1.log"; }
tap() { ADB shell input tap $1 $2; }

for zpd in false true; do
  write_config "$CREDS" $zpd ttff
  launch; sleep 50; grab ttff-zpd-$zpd; shot ttff-zpd-$zpd
done

write_config "$CREDS" false session
launch; sleep 22
shot tap-before
tap 220 1998; sleep 5
shot tap-after
tap 838 2274; sleep 1                       # Stats
tap 648 2274; sleep 12                      # Refresh (mid-session rtcConfiguration -> ICE restart)
shot after-refresh
tap 838 2274; sleep 2
tap 456 2274; sleep 12                      # KillWS: signalling dropped, pc untouched
shot after-killws
tap 838 2274; sleep 2
tap 258 2274; sleep 20                      # Connect: full reconnect
shot after-reconnect
tap 838 2274; sleep 1
tap 540 1200; sleep 4                       # tap again after reconnect
shot tap-after-reconnect
tap 838 2274; sleep 1
grab session
ADB shell wm size
