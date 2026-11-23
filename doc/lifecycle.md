← [README](../README.md) · [Partner guide](https://docs.mobilerun.ai/partners)

# Session and app lifecycle

The package connects to a Mobilerun cloud device and recovers from failures,
exactly like `@mobilerun/react`. Install version 0.1.0 from the `v0.1.0` git tag
as shown in the [installation instructions](../README.md#install).

The default connectivity snapshot arrives asynchronously. Attaching the adapter
before `start()` begins observation, but does not synchronously seed availability.
For a launch-offline guarantee, supply your own snapshot before `start()` as below
(using `connectivity_plus`, declared and imported by the host app).

```dart
final session = DeviceStreamSession(
  // Called at start, once per recovery cycle and when a token is rejected.
  // Return null while the device is not ready yet.
  credentials: () async => StreamCredentials(
    url: streamUrl,
    tokenProvider: () => backend.mintStreamToken(deviceId),
  ),
);
session.status.addListener(() => print(session.status.value));
final routes = await Connectivity().checkConnectivity();
session.setNetworkAvailable(routes.any((route) => route != ConnectivityResult.none));
final lifecycle = StreamLifecycle(session: session);
session.start();

// Inside a bounded area (for example Expanded):
DeviceStream(session: session, observeLifecycle: false);

final png = await session.screenshot();

lifecycle.dispose();
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
`token` example below uses a **device token (legacy)** (deprecated) and reuses the same token on every
reconnect; use the [token provider](stream-tokens.md) for single-use stream tokens:

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
and wake pending reconnects on foreground transitions. The default connectivity
source is `connectivity_plus` 7.3.2 on Android and iOS. A supplied `Stream<bool>`
`connectivity` replaces that source; `updateConnectivity(null)` restores it.
The adapter subscribes before checking the initial snapshot and refreshes the
platform snapshot on resume. Stale snapshots and detached-source events are ignored.

Availability starts unknown and optimistic. An initial offline observation blocks
discovery, token-provider calls and new sockets immediately; starting offline shows
`StreamUnavailable` and Retry without reporting an error. Going offline cancels
retry/watchdog waits and invalidates pending acquisition without reporting a failure;
late tokens are discarded. Healthy connected media is retained until its transport
actually fails. Foreground wake and target updates cannot bypass offline.
An explicit `retry()` overrides the offline hint for one fresh attempt with a reset
counter and fresh stream token; repeat taps while it is live and Retry on healthy
connected media do nothing. If it fails offline, `StreamUnavailable` exposes Retry
again and the error has `isFinal: true` because the SDK stopped retrying.
A real offline → online transition resets backoff and the retry budget and starts
one immediate attempt with a fresh stream token, even after Unavailable. A forced
attempt still waiting on its provider is discarded; one that already allocated its
socket continues with its watchdog. Duplicate online observations and healthy
connected sessions do not remount. Route availability
is advisory and does not guarantee Internet or server reachability; iOS simulator
network changes can miss observations.

Headless/custom owners can instead forward availability with
`session.setNetworkAvailable(false/true)`, visibility with `session.setVisible`,
and foreground wake with `session.handleWake()`. The app still owns session
`start()` and `close()`. If an adapter is removed while its session continues,
replace the network observer or explicitly set availability; disposal retains the
last observation. `DeviceStream(observeLifecycle: false)` has the same responsibility.

The default [sample](../example/lib/main.dart) combines stream controls, themes,
labels, stats and a local approval demo. See [TESTING.md](../TESTING.md).
