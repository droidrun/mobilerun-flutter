#!/bin/zsh
# Release arm64 size of the spike app vs. a stock Flutter app (no WebRTC). Usage: size.sh OUT_DIR
source "$(dirname "$0")/lib.sh"
OUT=$1; mkdir -p $OUT
APP=$(cd "$(dirname "$0")/.." && pwd)
cd $APP && flutter build apk --release --target-platform android-arm64 --split-per-abi || exit 1
cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk $OUT/spike-arm64-release.apk
B=$(mktemp -d)/baseline
flutter create --platforms=android --org ai.mobilerun.spike --project-name baseline_app $B >/dev/null || exit 1
cd $B && flutter build apk --release --target-platform android-arm64 --split-per-abi || exit 1
cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk $OUT/baseline-arm64-release.apk
ls -l $OUT/*.apk
