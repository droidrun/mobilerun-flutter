# Try the Flutter SDK

Tested with Flutter 3.47.9 (bundled Dart 3.13.7); add Flutter to PATH. For Android, install JDK 17,
Android SDK platform 36, build-tools, platform-tools, the emulator and an API 35+
AVD through Android Studio. Set JAVA_HOME and ANDROID_HOME and accept the SDK
licenses (`flutter doctor --android-licenses`). On macOS, iOS additionally needs
Xcode with an iOS simulator runtime; verify setup with `flutter doctor`.

## Credentials and launch

Use an existing device in your Mobilerun account. The preferred launch file contains
no credentials:

```json
{"helperBaseUrl":"http://localhost:3001","deviceId":"DEVICE_UUID"}
```

Start the [local backend helper](example/README.md) with the parent API key in its
process environment only, then launch the sample:

```sh
tool/run-sample.sh /path/to/sample.json
# macOS, optional:
tool/run-sample.sh /path/to/sample.json --ios
```

The helper uses `@mobilerun/sdk@6.3.0`: metadata via `sdk.devices.get(id)`, then
`sdk.streamTokens.create({deviceId,ttlSeconds:120},{maxRetries:0})` for minting,
with no automatic mint retry. The upstream wire endpoint remains
`POST /v1/identity/stream-keys`. Only metadata and the single-use mint DTO cross the local helper boundary.
The mint route and DTO retain their transitional wire names.
The app keeps an immutable helper/device binding and mints once per new socket.
It stores no minted stream tokens in app state, launch JSON, UI or logs. Never put an API key,
keyId or expiresAt in app configuration.

The runner copies launch bytes to app-private storage. The app reads and deletes that
file once, including invalid input. Android uses an owned emulator with an `adb reverse`
port mapping, removed during cleanup; the helper still binds only `127.0.0.1`.
The helper rejects foreign Host headers and all Origin or Sec-Fetch-Site headers (403/no-store).

The manual form and old `{"streamUrl":"wss://…","streamToken":"…"}` file remain
**device token (legacy) diagnostics**. The token entry is obscured. This static path reuses its token;
a pasted single-use stream token cannot reconnect. E2E/benchmark launch formats remain static.

Provider callbacks must be non-blocking (offload blocking/CPU work with `compute` or
`Isolate.run`). Pending Futures time out at 10 seconds without fallback. The 45-second
connect watchdog and 15-second handshake phase budgets start at socket allocation.
Close 1001 immediately clears media, peer, channels, timers and screenshots in every mode,
then schedules bounded reconnect with a fresh provider stream token (static mode reuses its token);
other Flutter closes retain their existing rebuild behaviour.

Create an AVD before running. SAMPLE_AVD selects it; SAMPLE_EMULATOR_PORT selects
an unused even port (default 5582). Close other instances of that AVD first. The
script refuses an occupied port and never reuses another running emulator. On
iOS it creates a temporary iPhone 17 simulator; SAMPLE_IOS_RUNTIME can select an
installed runtime identifier; otherwise the newest available runtime is selected.
A full Xcode installation with Simulator.app is required; the script checks this
before building. Keep the script running while testing; Ctrl-C stops its emulator
or deletes its temporary simulator.

## What to try

Use harmless apps and existing text fields on the remote device. Changes to that
device persist. Every row gives the expected result.

| Try | Expected result |
|---|---|
| Connect / first frame | Connecting gives way to live video with preserved aspect ratio. |
| Tap | The remote control responds, including near the picture's edges. |
| Swipe | A scrollable remote screen scrolls in the drag direction. |
| Two fingers | Zoomable content zooms. Use the emulator's multitouch controls or its pinch modifier. Simulator gesture support depends on the host. |
| Type Latin, emoji and CJK | Focus a remote editor, tap the picture and use Keyboard. Latin text arrives; composition commits as text. **Known limitation:** emoji and some CJK may not arrive; see below. |
| Back / Home / Recent | Each navigation button performs its remote Android action, including from the iOS host. |
| Rotate | Rotate the host emulator/simulator; video stays fitted and taps remain aligned. Rotate the remote app too if it supports rotation. |
| Background / foreground | Press the host Home button and reopen the sample; streaming resumes or recovers. |
| Network off / on | Disable host connectivity and restore it; recovery produces video again. On Simulator, use the host's network controls if available. |
| Forced reconnect | Tap Reconnect; a new session produces video. |
| Unavailable / Retry | Connect with an invalid token and wait for attempts to exhaust; Unavailable and Retry appear. Retry tries again. Restore valid credentials using Credentials and Connect. |
| Themes / labels | Light, Dark and Brand change tokens; Brand uses green controls, rounded corners, Allow / Decline approval labels. Stream labels are visible during live testing. |
| Demo approval | A 30-second countdown appears. Approve or Deny removes the card and shows the decision plus refetch count. Repeat for the other action. No real task is sent. |
| Stats | Stats shows updating fps, payload kbit/s, RTT, jitter-buffer delay, local/remote ICE candidates and first-frame ms. Unsupported values show —. Hide stats removes it. |

Typical emulator values: first frame about 4–7 seconds, 40–45 fps, network round trip about 20–30 ms and tap response about 350 ms.

## Automated checks

```sh
flutter pub get
flutter pub get --directory example
flutter analyze
dart format --set-exit-if-changed .
flutter test
(cd example && flutter test && flutter build apk --debug)
dart run tool/api_dump.dart --check
flutter pub publish --dry-run
(cd example/backend && npm ci && node --test server.test.mjs)
```

Sample tests cover helper/device binding, safe HTTP errors, mint timing and launch-file validation, one-time deletion, token-field masking,
themes/approval labels and local approval decisions/refetch. Library tests cover
stream lifecycle, input, approvals, credential redaction, statistics and default UI.
CI runs both suites and builds the Android sample.

Maintainers can run `example/tool/e2e_android.sh CREDENTIALS_JSON OUT_DIR` for
scripted Android input, reconnect and screenshot checks, or `tool/benchmark.sh`
for the [benchmark procedure](tool/BENCHMARK.md).

For host widget tests, `DeviceStream` installs connectivity observation by default.
Pass a controlled `connectivity:` stream (for example `const Stream<bool>.empty()`),
set `observeLifecycle: false` when the host owns lifecycle testing, or mock both
`dev.fluttercommunity.plus/connectivity` (the initial list such as `['wifi']` or
`['none']`) and `dev.fluttercommunity.plus/connectivity_status` (listen/cancel).
The default platform seed is asynchronous; explicitly set session availability before
`start()` when testing launch-offline suppression.

## Known limitations

Emulator multitouch and IME support depend on host configuration.
Some emoji and CJK characters may not arrive on Cloud Android devices through text injection.
