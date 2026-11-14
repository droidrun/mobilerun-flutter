# mobilerun-flutter

Flutter package for embedding Mobilerun device streaming and events.

## Status: pre-release

The package connects to a Mobilerun cloud device and recovers from failures,
exactly like `@mobilerun/react`. It has no touch or keyboard mapping and no
video widget yet; those come next. The package is not published yet and its
API may still change.

```dart
final session = DeviceStreamSession(
  // Called at start, once per recovery cycle and when a token is rejected.
  // Return null while the device is not ready yet.
  credentials: () async => StreamCredentials(url: streamUrl, token: token),
);
session.status.addListener(() => print(session.status.value));
session.start();

// Render session.videoStream with RTCVideoView, then send raw control bytes:
session.sendControl(encodeKeycode(action: AndroidKeys.actionDown, keycode: AndroidKeys.keycodeHome));
final png = await session.screenshot();

await session.close();
```

- `status` is `StreamConnecting`, `StreamConnected`, `StreamReconnecting(attempt)`
  or `StreamUnavailable`; `retry()` starts a new cycle from unavailable.
- `videoStream` is the stream for an `RTCVideoView`; `videoSize` is its size.
- `sendControl` and `sendHover` return false and drop the message while their
  data channel is not open. Hover never goes over the control channel.
- `StreamConfig` mutes the audio and enables zero playout delay by default.
  The playout delay setting is process-wide: the first session decides it.
- The signalling socket is the lifetime of the session on the server: a closed
  socket, like a failed peer connection, rebuilds both (exponential backoff,
  unavailable after six attempts).
- The video codec offer is VP9, H.265, H.264 in that order, and H.264 only
  when the device has no H.265 decoder.

Layout:

- `lib/src/protocol/`: constants, the binary control message encoders and the
  typed signalling messages.
- `lib/src/core/`: the session state machine and the reconnect controller. They
  run on the `SignallingConnector` and `PeerTransportFactory` interfaces and an
  injectable `Scheduler`, so they are tested with fake transports and a virtual
  clock.
- `lib/src/webrtc/`: the `web_socket_channel` and `flutter_webrtc`
  implementations of those interfaces.
- `example/`: a sample app, plus `example/tool/e2e_android.sh`, a scripted
  emulator run against a cloud device (first frame, control bytes, forced
  socket close, credential refresh).

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

Every test is data-driven over the fixture files and named after the fixture
case it checks.

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
