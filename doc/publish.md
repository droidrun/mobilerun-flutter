# Microphone and camera publish

Publishing sends the local microphone and optionally camera into the remote
device's virtual inputs over the existing viewer connection. It does not change
received audio mute, video rendering, credentials or viewer reconnect policy.
Android and iOS are supported; this does not add Flutter desktop or web support.

## Device capabilities and connection setup

Your backend reads `GET /v1/devices/{deviceId}/capabilities` and passes the
`.capabilities` snapshot to the app. Keep privileged API credentials on your
backend. A stream token cannot call the capabilities endpoint.

```dart
final session = DeviceStreamSession(
  credentials: () async => StreamCredentials(
    url: streamUrl,
    tokenProvider: () => backend.mintStreamToken(deviceId),
  ),
  config: const StreamConfig(
    publishCapabilities: DevicePublishCapabilities(
      microphoneInjection: true,
      cameraInjection: true,
      mediaInjectionTransport: 'direct',
    ),
  ),
  onError: (error) {
    if (error.operation == 'publish') {
      // Branch on error.reason.code, detail and serverReason.
    }
  },
);
```

Use actual response values; do not hard-code support in an integration.
Microphone support and the `direct` transport are required. Camera also requires
camera support and a local H.264 packetization-mode 1 encoder (supported profiles
42e0, 42c0, 4d00, 640c with any level ≥ 0x1f, baseline preferred; the
platform-offered level is preserved). Audio uses Opus/48000/2.
The first offer reserves trackless upstream sections without permission prompts.
If valid SSRC-bearing reservations cannot be produced, publication reports
`publish_unsupported` while viewing continues. An inactive answer never proves
that the viewer lacks permission. Configuration is immutable: use a new session
and fresh viewer credentials to change the capability snapshot.

## Host permissions

The SDK uses `flutter_webrtc` permission handling, without another permission
plugin. An explicit `startPublish` sends the admission request first. Only a
matching `accepted` (or `active`, which implies acceptance) opens local inputs
and requests permission. Refused or silent requests never prompt or capture.
Connecting and reconnecting never open local inputs.

Android hosts declare `android.permission.RECORD_AUDIO` and, when using video,
`android.permission.CAMERA`, alongside the existing `MODIFY_AUDIO_SETTINGS` and
`INTERNET` permissions. Runtime permission requests need a foreground Activity;
the plugin requests them only after server acceptance. Audio-only capture does
not request camera access.

iOS hosts **must** supply nonempty `NSMicrophoneUsageDescription` and, for video,
`NSCameraUsageDescription` values in their app Info.plist before invoking capture.
The pure Dart SDK cannot inspect the host bundle's privacy metadata through the
plugin API; missing usage descriptions can terminate the app. The example
includes both keys. Permission denial is `permission_denied/capture_permission`;
missing, busy or unreadable inputs are `publish_failed/capture_unavailable`.

Default microphone capture requests echo cancellation, noise suppression and
automatic gain control. Camera settings target up to 1280×720, ideal 24/max 30 fps,
and a best-effort 1,000,000 bit/s uplink cap. Hardware may choose a different
supported capture format. Capture is atomic: a camera failure releases the mic.

## Start, observe and stop

`startPublish(const PublishOptions(audio: true))` requests microphone only;
`video: true` requests both inputs. `audio: false` is rejected locally with
`publish_failed/invalid_options`; it never silently adds audio or drops video.
The signaling socket must be open and the viewer peer connected before capture.
A second pending/active request fails without changing the first operation.

`session.publishState` is a `ValueListenable<PublishState>` starting at `idle`.
It progresses through `starting`, `accepted`, `capturing`, and `active`.
Capture begins only after matching server acceptance and remains detached
until the requested inputs are ready. The start Future
resolves only after all requested inputs attach and the server reports active.
No acceptance within 5 seconds gives `publish_unsupported/response_timeout`;
failure to complete activation within 30 seconds from acceptance gives
`publish_timeout/active_timeout`. This window includes OS permission prompts,
capture, attachment and the server active response.

`stopPublish()` is idempotent and requires no server acknowledgement. It cancels
an outstanding start with `PublishException` / `publish_cancelled`, sets `stopped`
with reason `stopped_by_client`, and emits no error notification when the
stop write succeeds. A throwing start or stop socket write reports `disconnected`
and still releases all local capture. Late capture
results are stopped, and sender mutations remain serialized before a later start.
Stop then explicitly start again to add/remove camera; each start gets a new UUID.

Server `forbidden` maps to `publish_not_allowed`, `busy` to `publish_busy`, and
`unsupported` to `publish_unsupported`. Unknown terminal reasons fail safely as
`publish_failed`. String server reasons are preserved in `serverReason`.
Silence never becomes a fabricated permission denial. Failures appear in state,
the typed exception for a pending start, and once through `onError` with
`operation: 'publish'`, the current viewer attempt index, and `isFinal: true`.
They do not make an otherwise connected viewer unavailable.

Socket/peer loss, viewer replacement, session close and viewer unmount release
capture. Viewer replacement/unmount emits terminal `disconnected` and one publish
error. `close()` ends with a `stopped` snapshot and no later publish callbacks. Reconnect requires a new explicit user start; same-peer ICE credential
refresh preserves the publication. Track-ended notifications terminate the entire
publication. Delivery of native capture-interruption notifications depends on the
pinned plugin/platform; real Android/iOS permission revocation and interruption
behavior needs hardware validation. This native `onEnded` gap is a documented
v1.1 limitation of the pinned plugin. `StreamLifecycle` automatically stops publish
when the app enters the background and never resumes it on foreground. Headless
apps attach `StreamLifecycle`; apps that opt out of SDK lifecycle observation
report visibility through `session.setVisible`.

## Built-in controls and labels

The default `DeviceStream` places the microphone/camera pill at the bottom centre
inside the video area. It overlays the video without changing its bounds. Live
icons use `StreamTokens.destructive`; all other colors and typography come from
`StreamTheme`. Only the two buttons consume taps; the pill background and
status text pass taps through to the device stream. Status text sits above the
pill. After three seconds without interaction the pill fades to 50% opacity;
pointer/touch interaction near it restores full opacity without a layout shift.
Buttons are disabled during capture/start/acceptance. The camera
control is offered only with device support and a valid local camera reservation.
Microphone off stops the complete publication; camera toggles explicitly stop
then restart the requested input combination.

Set `showPublishControls: false` for headless controls. Missing or incompatible
capabilities or a `publish_unsupported` outcome hide the pill. `hasControl` is not publish authorization; only the
server decides. Every rendered label can be overridden through `StreamLabels`:
`microphone`, `camera`, `stopMicrophone`, `stopCamera`, `publishStarting`,
`publishPermissionDenied`, `publishNotAllowed`, and `publishFailed`.
