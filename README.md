# mobilerun-flutter

Flutter package for embedding Mobilerun device streaming, remote input and task approvals for Android and iOS.

## Installation

Install from source until the first release: `flutter pub add mobilerun_flutter --git-url https://github.com/droidrun/mobilerun-flutter.git`.
After the first release, add `mobilerun_flutter: ^0.1.0` to your dependencies.

The host Android app needs `<uses-permission android:name="android.permission.INTERNET" />`
in `android/app/src/main/AndroidManifest.xml`, including release builds. Set
`uses-material-design: true` under `flutter:` in the host's `pubspec.yaml` for the default UI icons.

See [TESTING.md](TESTING.md) to launch the interactive sample and try every feature.

## Quickstart

The package connects to a Mobilerun cloud device and recovers from failures,
exactly like `@mobilerun/react`. The package is not published yet and its
API may still change.

```dart
final session = DeviceStreamSession(
  // Called at start, once per recovery cycle and when a token is rejected.
  // Return null while the device is not ready yet.
  credentials: () async => StreamCredentials(url: streamUrl, token: token),
);
session.status.addListener(() => print(session.status.value));
session.start();

// Inside a bounded area (for example Expanded):
DeviceStream(session: session);

final png = await session.screenshot();

await session.close();
```

- `status` is `StreamConnecting`, `StreamConnected`, `StreamReconnecting(attempt)`
  or `StreamUnavailable`; `retry()` starts a new cycle from unavailable.
- After `close()`, status keeps its last value, stops updating, and controls are disabled.
- `videoSize` includes decoded width, height and clockwise rotation in degrees.
  Rotation is 0 unless a `DeviceStreamView` renders the session. The view uses the renderer
  dimensions and rotation for displayed video coordinates.
- Raw channel sends are internal; use `DeviceStreamView` for input mapping.
  Hover never goes over the control channel.
- `StreamConfig` has `muted` (default `true`) and `videoCodec` (default
  `VideoCodec.automatic`). `setMuted` changes audio on the current and later
  connections. `VideoCodec.h264Only` offers H.264 and its auxiliary codecs only.
  The SDK initializes WebRTC with zero playout delay before creating a renderer
  or peer connection; no plugin setup is needed in the host app. An app that
  initializes `flutter_webrtc` itself first keeps its own initialization options.
- The signalling socket is the lifetime of the session on the server: a closed
  socket, like a failed peer connection, rebuilds both (exponential backoff,
  unavailable after six attempts).
- The video codec offer is VP9, H.265, H.264 in that order, and H.264 only
  when the device has no H.265 decoder.

## Video and input

```dart
final view = DeviceStreamController();

// Place in a bounded area, such as an Expanded in a Column.
DeviceStreamView(session: session, hasControl: true, controller: view);

view.showKeyboard();
view.hideKeyboard();
view.sendSystemKey(SystemKey.back); // also home and recent
```

The view renders video with contain fit and transparent letterboxing. It
rebuilds on renderer changes, including reconnection and rotation. Touches
outside the video are ignored; releases use the last position inside it.
Up to ten fingers have stable slots, with MOVE coalesced per display frame.
Mouse hover uses only the separate hover channel. Wheel and trackpad pan
use the same pixel-to-tick conversion as the React SDK.

Click or tap the picture to focus hardware input. Printable keys send text;
control/navigation keys send Android keycodes. Cmd/Ctrl+V pastes the local
clipboard through SET_CLIPBOARD; Cmd/Ctrl+M sends MENU. Only an explicit `showKeyboard()` call opens the soft keyboard: marked IME text stays local until committed; deletion
and enter send DEL and ENTER pairs. Suggestions and autocorrection are disabled;
CJK composition and emoji remain available.
Hiding the keyboard finalizes composition only when the view owns the input;
a host editor’s keyboard is left alone.
The view does not keep a copy of the remote editor's contents or selection.

`hasControl: false` renders the picture and sends no input. This switch controls
local interaction; the service remains responsible for permissions. The app
owns the session lifecycle and must close the session when finished.

Host back gestures/buttons are never forwarded automatically. Apps may wire
an explicit back action with `PopScope` (choose whether the host route pops):

```dart
PopScope(
  canPop: false,
  onPopInvokedWithResult: (didPop, result) {
    if (!didPop) view.sendSystemKey(SystemKey.back);
  },
  child: DeviceStreamView(session: session, hasControl: true, controller: view),
);
```

Use `session.openUrl(url)` to open a URL on the remote device. Until the control
channel opens, the session queues only the latest URL. The method returns nothing.
`session.screenshot()` returns PNG bytes or throws a `StreamException` subtype:
`StreamNotConnectedException`, `StreamDisconnectedException`,
`ScreenshotFailedException`, or `ScreenshotTimeoutException`.

Behaviour is checked against the shared conformance fixtures vendored in
`conformance/fixtures` (the pinned tag is in `conformance/VERSION`).

## Development

Use Flutter 3.47.9 (including its bundled Dart SDK).
See [RELEASING.md](RELEASING.md) for publisher setup and release steps.

```sh
flutter pub get
flutter pub get --directory example
flutter analyze
dart format --set-exit-if-changed .
flutter test
dart run tool/api_dump.dart --check
flutter pub publish --dry-run
```

Protocol tests use the shared fixtures. Input tests cover geometry, pointer
slots, scroll, key routing, IME composition and widget-level event routing.

### Updating the fixtures (maintainers)

```sh
tool/sync-conformance.sh TAG PATH_TO_CONFORMANCE_CLONE
dart run tool/generate_constants.dart
dart run tool/generate_key_codes.dart
```

The first command replaces `conformance/fixtures` with the copy at the given
release tag. The second regenerates `lib/src/protocol/constants.dart` from
`constants.json`; the third regenerates keyboard mappings. Always pin a tag, never a branch.

## Default UI and approvals

`DeviceStream`, `StreamNavigationBar`, `TaskApprovalCard`,
`StreamStatusPill`, `StreamTheme`, `StreamLabels`, and `TaskApprovalLabels` are
optional white-label widgets. They display no logo or product name. The
headless session and approval controller also work with your own UI.

### Stream with default chrome

Use `DeviceStream` in a bounded area to compose the existing `DeviceStreamView`
video/input widget with status overlays and Back/Home/Recent navigation:

```dart
DeviceStream(
  session: session,
  hasControl: true,
  controller: view,
  labels: const StreamLabels(connecting: 'Starting device'),
  // navigationBuilder: (_, _) => const SizedBox.shrink(),
  // connectivity: existingOnlineStream,
);
```

Connecting and reconnecting show a corner spinner and label; reconnect attempts
use `reconnectingAttempt` after the first failure. A connected stream shows the
video. Unavailable shows a message and Retry, calling `session.retry()`. Local
input and navigation share `hasControl && status is! StreamUnavailable`.
Display-only mode keeps video visible. Navigation sends explicit Back/Home/Recent
DOWN/UP pairs (4/3/187); it never handles host back implicitly.

The app still owns `session.start()` and `session.close()`. By default the view
attaches `StreamLifecycle`; set `observeLifecycle: false` if your app already
owns one. Initial online/foreground snapshots and visible focus changes do not
wake reconnects. App background pauses keepAlive; foreground wakes pending reconnects. Network
return wakes pending reconnects when you provide the app's `connectivity` stream.

Every slot has its default builder as an explicit default value:

- `placeholderBuilder(context, StreamOverlayState)` replaces the connecting
  overlay. Its state supplies status, localized labels and `retry`. The returned
  widget is placed inside the bounded stream container.
- `unavailableBuilder(context, StreamOverlayState)` replaces the unavailable
  overlay and can call `state.retry()`.
- `navigationBuilder(context, StreamNavigationState)` replaces navigation,
  receiving `canControl`, labels and `onAction` in one object.

You can call `defaultStreamPlaceholder`, `defaultStreamUnavailable`, or
`defaultStreamNavigation` inside your builder to wrap the defaults. The bare
`DeviceStreamView` remains available for fully custom UI.

### Task approvals

The backend owns approval state and permissions. Your app provides callbacks
to your own authenticated backend; the SDK never handles an account API key.
**An API key must never ship in a Flutter app**, including build-time defines.
Your backend checks task ownership before fetching or deciding an approval.

```dart
final approvals = TaskApprovalController(
  taskId: taskId,
  fetchApproval: (id) => backend.fetchApproval(id),
  decide: (request) => backend.decideApproval(
    request.taskId,
    request.approvalId,
    request.decision.name, // "approve" or "deny"
  ),
  // Optional: change events are hints to fetch again, never authoritative data.
  // subscribe: (id, onChange) => backend.subscribe(id, onChange),
);

ListenableBuilder(
  listenable: approvals,
  builder: (context, _) {
    final state = approvals.state;
    return TaskApprovalCard(
      approval: state.approval,
      onDecide: approvals.decide,
      isPending: state.isDeciding,
      decision: state.decision,
      error: state.error?.toString(), // Or map the raw error to localized text.
      labels: const TaskApprovalLabels(approve: 'Allow', deny: 'Decline'),
      // device: yourDeviceWidget,
    );
  },
);

// Changing tasks invalidates every old fetch and decision result.
approvals.update(taskId: nextTaskId); // null disables fetching.
// An omitted enabled argument preserves the previous enabled state.
// Detach the push subscription and cancel polling when the owner goes away.
approvals.dispose();
```

The controller fetches immediately, then three seconds after each completed
fetch when no subscription is supplied or subscribing fails. A subscription
failure is reported through the controller error output. With a working subscription it fetches on
change hints, explicit `refetch()`, and after decisions. Newer overlapping
fetches win; task changes, disabling and disposal invalidate older results.
Both decision buttons are disabled only while deciding. The backend decides
whether an approval has expired; the isolated countdown is display-only and
stops ticking at expiry. Any decision failure (including HTTP 404/409 and an
integrator timeout/cancellation) shows an error and refetches. A successful
fetch clears fetch errors; a decision error remains until the next decision or
task change. Subscription and error-observer exceptions are guarded.

`PendingApproval` accepts unknown kinds. Valid `payment_card` details display
`label` (falling back to `credentialName`), `targetPackage`, and optional
`targetHost`. Other kinds and invalid details show the generic waiting title
with the same buttons. A null approval renders nothing. An optional `device`
slot stays mounted across the Details/Device switch and the 768-pixel wide
breakpoint. The app owns any surrounding sheet or dialog.

`actionsBuilder` receives one `ApprovalActionsState` with labels, deciding
state, and `onDecide`. Its default is `defaultApprovalActions`; a custom builder
can call that function to retain or wrap the defaults.

### Styling and labels

All SDK components use React's neutral light defaults, independently of the
host's Material theme. Dark mode is opt-in:

```dart
StreamTheme(
  tokens: const StreamTokens().copyWith(
    primary: const Color(0xff005b50),
    radius: 10,
  ),
  // followSystem: true, // explicitly opt into the system's light/dark choice
  // tokens: StreamTokens.dark, // or always use dark
  child: yourSdkWidgets,
);
```

Every token is individually overridable: `background`, `foreground`, `card`,
`cardForeground`, `muted`, `mutedForeground`, `border`, `ring`, `primary`,
`primaryForeground`, `accent`, `accentForeground`, `destructive`, `radius`,
and `typography`. `radius` is a base radius, default 8 logical pixels: buttons
use `radius × 0.75` and cards use `radius + 4` (6 and 12 by default). Disabled buttons
dim as a whole. `StreamTokens.dark` mirrors React's `.dark` palette.

Colors are converted once from React's OKLCH tokens: OKLCH → OKLab → linear
sRGB (the standard D65 OKLab matrix), clamp to the sRGB gamut, apply the sRGB
transfer function, then round each channel to 8 bits. Neutral colors have zero
chroma; the dark border retains 10% white alpha. Examples: light background
`#ffffff`, foreground `#0a0a0a`, primary `#171717`, destructive `#e7000b`;
dark background `#0a0a0a`, primary `#fafafa`, destructive `#ff6467`.

`TaskApprovalLabels` provides React's approval label keys (`paymentCardTitle`,
`waiting`, `card`, `app`, `domain`, `timeLeft`, `expired`, `approve`, `deny`,
`viewSwitch`, `details`, `device`). `StreamLabels` provides stream/navigation
labels (`connecting`, `reconnecting`, `reconnectingAttempt`, `unavailable`,
`retry`, `back`, `home`, `recent`). `{time}` is replaced in `timeLeft`;
`{attempt}` and `{max}` are reconnect template fields. Backend values are
rendered as supplied; the card accepts a `String?` error so the app can map
and localize the controller's raw error. Changed error text is announced once,
assertively. Identical poll results do not notify listeners.

Tokens, labels, pending approvals and controller snapshots use value equality.
Tokens, labels and integrator-supplied `PendingApproval` values support `copyWith`.
SDK-created values and slot state are read-only snapshots.

### Credentials and app lifecycle

Pass your existing backend call directly as the session's provider:

```dart
final session = DeviceStreamSession(
  credentials: () async {
    final device = await backend.fetchDevice();
    if (device.streamUrl == null) return null;
    return StreamCredentials(url: device.streamUrl!, token: device.streamToken);
  },
)..start();
```

The session owns credentials discovery. Before the first target, null, throwing
and timed-out provider calls poll again after 3,000 ms without consuming the
reconnect budget. Each call is bounded by 45 seconds;
`handleWake()`/`retry()` can supersede a pending initial call. After discovery, remounts reuse
the cached target while a heal refreshes credentials in the background. A null
or failed refresh retains that target, so connection failures still exhaust
the retry budget and show Unavailable + Retry. A token-only credential change
while connected is cached for the next mount; a URL change, or any credential
change while not connected, remounts when the current backoff permits it.
An empty or null token leaves the URL unchanged; other tokens are percent-encoded.
Credential debug descriptions redact both URL and token. Closing cancels timers and
ignores late provider results.

For a custom UI, create a `StreamLifecycle(session: session)` once and dispose
it with the UI. It uses `AppLifecycleListener` to pause keepAlive while hidden
and wake pending reconnects on foreground transitions. Optionally pass your
app's existing `Stream<bool>` as `connectivity`; only lost → available wakes,
never the initial online snapshot. Use `updateConnectivity` to replace the
source while retaining its last online state. The SDK adds no connectivity dependency: network-return wake needs your app's
existing connectivity stream.
You can instead call `session.setVisible(false/true)` and `session.handleWake()`
from your existing lifecycle/network integration. The app owns session
`start()` and `close()`.

The default [sample](example/lib/main.dart) combines stream controls, themes,
labels, stats and a local approval demo. See [TESTING.md](TESTING.md).

## Stream statistics

`session.stats` is a read-only `ValueListenable<StreamStats?>`. Samples are
published once per second only while the session is connected, visible, and
has listeners; the value is null otherwise, including after close. Suppressed
ICE restart dips follow the session's connected state.

```dart
session.stats.addListener(() {
  final stats = session.stats.value;
  if (stats == null) return;
  print('${stats.fps} fps, ${stats.bitrateKbps} Kbit/s, ${stats.rttMs} ms RTT');
});
```

`StreamStats` is an immutable, SDK-created value. Optional fields include video
dimensions, codec, bitrate, selected ICE pair RTT, separate local/remote candidate
types, lost packets, dropped frames, freezes, jitter-buffer/decode duration per
frame, and time to the first observed decoded frame. Unsupported values and the
first counter-derived rates remain null. Rates use one-second publishing ticks;
size-only polls do not advance their baselines. First-frame timing uses the
attempt's monotonic clock with a 50 ms polling interval until the first frame.
Value equality lets the notifier deduplicate unchanged samples.

See [the benchmark procedure](tool/BENCHMARK.md) for rendered tap-region and
app-launch latency measurements, steady rates, and lifecycle/memory checks.

## License

Apache-2.0, see `LICENSE`.
