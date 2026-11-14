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
