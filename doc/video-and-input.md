← [README](../README.md) · [Partner guide](https://docs.mobilerun.ai/partners)

# Video and input

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
