← [README](../README.md) · [Partner guide](https://docs.mobilerun.ai/partners)

# Default UI and styling

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

## Styling and labels

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
labels (`connecting`, `reconnecting`, `disconnected`, `reconnectingAttempt`,
`unavailable`, `retry`, `back`, `home`, `recent`). `disconnected` shows while
reconnecting after an open session dropped; `session.lastError` carries the reason. `{time}` is replaced in `timeLeft`;
`{attempt}` and `{max}` are reconnect template fields. Backend values are
rendered as supplied; the card accepts a `String?` error so the app can map
and localize the controller's raw error. Changed error text is announced once,
assertively. Identical poll results do not notify listeners.

Tokens, labels, pending approvals and controller snapshots use value equality.
Tokens, labels and integrator-supplied `PendingApproval` values support `copyWith`.
SDK-created values and slot state are read-only snapshots.
