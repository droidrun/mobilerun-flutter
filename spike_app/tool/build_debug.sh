#!/bin/zsh
# Debug build of the spike app (arm64). Needs ANDROID_HOME, JAVA_HOME and flutter on PATH.
source "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.." || exit 1
flutter build apk --debug --target-platform android-arm64
