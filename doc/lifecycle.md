← [README](../README.md) · [Partner guide](https://docs.mobilerun.ai/partners)

# Session and app lifecycle

The package connects to a Mobilerun cloud device and recovers from failures,
exactly like `@mobilerun/react`. The package is not published yet and its
API may still change.

```dart
final session = DeviceStreamSession(
  // Called at start, once per recovery cycle and when a token is rejected.
  // Return null while the device is not ready yet.
  credentials: () async => StreamCredentials(
    url: streamUrl,
    tokenProvider: () => backend.mintStreamKey(deviceId),
  ),
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

## Credentials and app lifecycle

Pass your existing backend call directly as the session's provider. The static
`token` example below is legacy (deprecated) and reuses the same token on every
reconnect; use the [token provider](stream-keys.md) for single-use keys:

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

The default [sample](../example/lib/main.dart) combines stream controls, themes,
labels, stats and a local approval demo. See [TESTING.md](../TESTING.md).
