#!/bin/zsh
# One emulator session: connect once, screenshot, dump logs. Usage: explore.sh CREDS_JSON OUT_DIR
source "$(dirname "$0")/lib.sh"
CREDS=$1; OUT=$2; SHOTS=$OUT/shots; mkdir -p $OUT $SHOTS
trap emu_stop EXIT
emu_start || exit 1
ADB install -r build/app/outputs/flutter-apk/app-debug.apk
ADB shell am start -n $PKG/.MainActivity >/dev/null; sleep 3; ADB shell am force-stop $PKG
write_config "$CREDS" false session
launch
sleep 45
shot explore-1
ADB logcat -d -s flutter | sed 's/^.*flutter *: //' > $OUT/explore.log
ADB shell wm size; ADB shell wm density
