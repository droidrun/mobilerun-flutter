# Try the Flutter SDK

Tested with Flutter 3.47.9 (bundled Dart 3.13.7); add Flutter to PATH. For Android, install JDK 17,
Android SDK platform 36, build-tools, platform-tools, the emulator and an API 35+
AVD through Android Studio. Set JAVA_HOME and ANDROID_HOME and accept the SDK
licenses (`flutter doctor --android-licenses`). On macOS, iOS additionally needs
Xcode with an iOS simulator runtime; verify setup with `flutter doctor`.

## Credentials and launch

Use a device in your Mobilerun account. Your backend fetches `streamUrl` and
`streamToken` via `GET /devices/{id}` and supplies them to the app. Never ship
an API key in an app. Create a local JSON file outside the checkout:

```json
{"streamUrl":"wss://your-stream-endpoint", "streamToken":"your-short-lived-token"}
```

```sh
tool/run-sample.sh /path/to/credentials.json
# macOS, optional:
tool/run-sample.sh /path/to/credentials.json --ios
```

The script builds the debug app, boots one emulator/simulator, installs the app,
loads the JSON into app-private storage and launches it. Android uses stdin with
`adb run-as`; iOS uses the simulator app's private container. The app reads and
deletes the launch file once, even when the JSON is invalid. The original file
stays on your machine; delete it when finished and never commit it. Credentials
then stay in memory, are never logged, and disappear when the process exits.
The token field is obscured. You can also paste credentials manually; Credentials
opens the form and Connect applies changes. The sample reuses the entered token;
load fresh values when it expires. Your production backend should refresh it.

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
| Swipe | A scrollable remote page scrolls in the drag direction. |
| Two fingers | A zoomable page zooms. Use the emulator's multitouch controls or its pinch modifier. Simulator gesture support depends on the host. |
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
```

Sample tests cover launch-file validation, one-time deletion, token-field masking,
themes/approval labels and local approval decisions/refetch. Library tests cover
credential token redaction and countdown ticking. Library suites
cover stream lifecycle, input, approvals and UI internals. CI runs both suites
and builds the Android sample.

## Known limitations

Events subscription awaits the backend token contract. Publishing has not happened;
install from source as described in README. Emulator multitouch and IME support
depend on host configuration. Emoji and some CJK may not arrive on Cloud Android
devices via text injection yet; the device-side fix is pending and affects every
client. This checklist item is a known limitation, rather than a passing delivery check.
