# mobilerun-flutter

Flutter package for embedding Mobilerun device streaming and events.

## Status: pre-release

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

final png = await session.screenshot();

await session.close();
```

- `status` is `StreamConnecting`, `StreamConnected`, `StreamReconnecting(attempt)`
  or `StreamUnavailable`; `retry()` starts a new cycle from unavailable.
- `videoSize` is the decoded frame size; the view uses the renderer
  dimensions and rotation for displayed video coordinates.
- Raw channel sends are internal; use `DeviceStream` for input mapping.
  Hover never goes over the control channel.
- `StreamConfig` starts the audio muted (`setMuted` changes it) and asks for
  zero playout delay. That setting is process-wide: call
  `WebRTC.initialize(options: {'zeroPlayoutDelay': true})` in `main()` before
  the first video renderer, see the example.
- The signalling socket is the lifetime of the session on the server: a closed
  socket, like a failed peer connection, rebuilds both (exponential backoff,
  unavailable after six attempts).
- The video codec offer is VP9, H.265, H.264 in that order, and H.264 only
  when the device has no H.265 decoder.

## Video and input

```dart
final view = DeviceStreamController();

// Place in a bounded area, such as an Expanded in a Column.
DeviceStream(session: session, hasControl: true, controller: view);

view.showKeyboard();
view.hideKeyboard();
view.sendSystemKey(DeviceSystemKey.back); // also home and recent
```

The view renders video with contain fit and transparent letterboxing. It
rebuilds on renderer changes, including reconnection and rotation. Touches
outside the video are ignored; releases use the last position inside it.
Up to ten fingers have stable slots, with MOVE coalesced per display frame.
Mouse hover uses only the separate hover channel. Wheel and trackpad pan
use the same pixel-to-tick conversion as the React SDK.

Click or tap the picture to focus hardware input. Printable keys send text;
control/navigation keys send Android keycodes. Cmd/Ctrl+V pastes the local
clipboard through SET_CLIPBOARD; Cmd/Ctrl+M sends MENU. The optional controller
opens a soft keyboard: marked IME text stays local until committed; deletion
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
    if (!didPop) view.sendSystemKey(DeviceSystemKey.back);
  },
  child: DeviceStream(session: session, hasControl: true, controller: view),
);
```

Layout:

- `lib/src/protocol/`: constants, the binary control message encoders and the
  typed signalling messages.
- `lib/src/core/`: the session, one connect attempt and the reconnect
  controller. They run on small transport interfaces and an injectable
  `Scheduler`, so they are tested with fake transports and a virtual clock.
- `lib/src/webrtc/`: the `web_socket_channel` and `flutter_webrtc`
  implementations of those interfaces.
- `example/`: a sample app, plus `example/tool/e2e_android.sh`, a scripted
  emulator run against a cloud device (video pixels, widget touch/swipe,
  two-finger input, keyboard/IME, navigation and rotated-view mapping).

Behaviour is checked against the shared conformance fixtures vendored in
`conformance/fixtures` (the pinned tag is in `conformance/VERSION`).

## Development

```sh
flutter pub get
flutter pub get --directory example
flutter analyze
dart format --set-exit-if-changed .
flutter test
```

Protocol tests use the shared fixtures. Input tests cover geometry, pointer
slots, scroll, key routing, IME composition and widget-level event routing.

### Updating the fixtures

```sh
tool/sync-conformance.sh TAG PATH_TO_CONFORMANCE_CLONE
dart run tool/generate_constants.dart
```

The first command replaces `conformance/fixtures` with the copy at the given
release tag. The second regenerates `lib/src/protocol/constants.dart` from
`constants.json`. Always pin a tag, never a branch.

## License

Apache-2.0, see `LICENSE`.

## Default UI and approvals

`DeviceStreamView`, `StreamNavigationBar`, `TaskApprovalCard`,
`StreamStatusPill`, `StreamTheme`, and `StreamLabels` are
optional white-label widgets. They display no logo or product name. The
headless session and approval controller also work with your own UI.

### Stream with default chrome

Use `DeviceStreamView` in a bounded area to compose the existing `DeviceStream`
video/input widget with status overlays and Back/Home/Recent navigation:

```dart
DeviceStreamView(
  session: session,
  hasControl: true,
  controller: view,
  labels: const StreamLabels(connecting: 'Starting device'),
  // showNavigation: false,
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
attaches `StreamLifecycle`; set `handleLifecycle: false` if your app already
owns one. Initial online/foreground snapshots and visible focus changes do not
wake reconnects. App background pauses keepAlive; foreground/network return
wakes pending reconnects.

Every slot has its default builder as an explicit default value:

- `placeholderBuilder(context, StreamOverlayState)` replaces the connecting
  overlay. The scope supplies status, localized label, bounded container
  constraints and `retry`.
- `unavailableBuilder(context, StreamOverlayState)` replaces the unavailable
  overlay and can call `state.retry()`.
- `navigationBuilder(context, StreamNavigationState)` replaces navigation,
  receiving `canControl`, labels and `onAction` in one object.

You can call `defaultStreamPlaceholder`, `defaultStreamUnavailable`, or
`defaultStreamNavigation` inside your builder to wrap the defaults. The bare
`DeviceStream` remains available for fully custom UI.

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
      error: state.error,
      labels: const StreamLabels(approve: 'Allow', deny: 'Decline'),
      // device: yourDeviceWidget,
    );
  },
);

// Changing tasks invalidates every old fetch and decision result.
approvals.update(taskId: nextTaskId);
// Detach the push subscription and cancel polling when the owner goes away.
approvals.dispose();
```

The controller fetches immediately, then three seconds after each completed
fetch when no subscription is supplied. With a subscription it only fetches on
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
and `typography`. Default button radius is 6 logical pixels. Disabled buttons
dim as a whole. `StreamTokens.dark` mirrors React's `.dark` palette.

Colors are converted once from React's OKLCH tokens: OKLCH → OKLab → linear
sRGB (the standard D65 OKLab matrix), clamp to the sRGB gamut, apply the sRGB
transfer function, then round each channel to 8 bits. Neutral colors have zero
chroma; the dark border retains 10% white alpha. Examples: light background
`#ffffff`, foreground `#0a0a0a`, primary `#171717`, destructive `#e7000b`;
dark background `#0a0a0a`, primary `#fafafa`, destructive `#ff6467`.

`StreamLabels` provides all React approval label keys (`paymentCardTitle`,
`waiting`, `card`, `app`, `domain`, `timeLeft`, `expired`, `approve`, `deny`,
`viewSwitch`, `details`, `device`) plus stream and navigation labels
(`connecting`, `reconnecting`, `reconnectingAttempt`, `unavailable`, `retry`,
`back`, `home`, `recent`). `{time}` is replaced in `timeLeft`;
`{attempt}` and `{max}` are the reconnect template fields. Backend-provided
values and error messages are rendered as supplied; localize those in your
backend or integrator callbacks. Public value types use named defaults and
`copyWith`, allowing individual overrides without rebuilding every field.

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

The session is the only credential-poll owner: null means not ready and polls
again after 3,000 ms without consuming reconnect attempts. Healing refetches
credentials through that same provider. Closing cancels polling and ignores
late provider results.

For a custom UI, attach a `StreamLifecycle(session: session)` once and dispose
it with the UI. It uses `AppLifecycleListener` to pause keepAlive while hidden
and wake pending reconnects on foreground transitions. Optionally pass your
app's existing `Stream<bool>` as `connectivity`; only lost → available wakes,
never the initial online snapshot. No connectivity dependency is required.
You can instead call `session.setVisible(false/true)` and `session.wake()`
from your existing lifecycle/network integration. The app owns session
`start()` and `close()`.

The offline gallery demonstrates themes, label overrides, countdowns and a
fake approval backend, including approve/deny → refetch and decision errors:

```sh
cd example
flutter run -t lib/ui_gallery_main.dart
```

The stream chrome gallery uses a local credentials provider to exercise
connecting, reconnecting, unavailable/retry, custom slots and themes without
opening a cloud device: `flutter run -t lib/ui_stream_gallery_main.dart` from
`example/`. It does not simulate connected video.
