// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../core/device_stream_session.dart';
import '../core/input/input_geometry.dart';
import '../core/input/key_input.dart';
import '../core/input/physical_key_codes.dart';
import '../core/input/pointer_input.dart';
import '../core/input/scroll_input.dart';
import '../core/input/stream_text_input.dart';
import '../protocol/constants.dart';
import '../protocol/control_messages.dart';

/// Explicit device navigation. Host OS back gestures are never forwarded.
enum DeviceSystemKey {
  /// Android BACK.
  back(AndroidKeys.keycodeBack),

  /// Android HOME.
  home(AndroidKeys.keycodeHome),

  /// Android recent apps.
  recent(AndroidKeys.keycodeAppSwitch);

  const DeviceSystemKey(this._keycode);
  final int _keycode;
}

/// Optional handle for one mounted [DeviceStream]. Calls while detached are
/// no-ops; input also requires the view's `hasControl` to be true.
final class DeviceStreamController {
  _DeviceStreamState? _state;

  /// The aspect-fit video rectangle, in view-local coordinates; null before
  /// the first frame or while no stream is attached.
  Rect? get renderedVideoRect => _state?._geometry?.rect;

  /// Focuses the view and opens the platform keyboard.
  void showKeyboard() => _state?._showKeyboard();

  /// Closes the platform keyboard and discards uncommitted composition.
  void hideKeyboard() => _state?._textInput.close();

  /// Sends one DOWN/UP pair for an explicit navigation action.
  void sendSystemKey(DeviceSystemKey key) {
    final state = _state;
    if (state != null && state.widget.hasControl) {
      pressKey(key._keycode, state._send);
    }
  }
}

/// Live device video with aspect-fit touch, mouse, scroll, keyboard and IME
/// input. Give this widget bounded width and height (for example `Expanded`).
///
/// The app owns [session]'s start/close lifecycle. `hasControl: false` renders
/// video and sends no input; the device service still decides permissions.
/// No navigation chrome or implicit host back handling is included.
class DeviceStream extends StatefulWidget {
  /// Creates a live video and input view.
  const DeviceStream({
    super.key,
    required this.session,
    required this.hasControl,
    this.controller,
    this.autofocus = false,
  });

  /// Session supplying video and the input channels.
  final DeviceStreamSession session;

  /// Whether this view should send local input.
  final bool hasControl;

  /// Optional keyboard and navigation handle; attach to only one view.
  final DeviceStreamController? controller;

  /// Whether to request hardware-key focus when mounted.
  final bool autofocus;

  @override
  State<DeviceStream> createState() => _DeviceStreamState();
}

class _DeviceStreamState extends State<DeviceStream> {
  final _renderer = RTCVideoRenderer();
  final _focus = FocusNode(debugLabel: 'DeviceStream');
  late final _pointers = PointerInput(_send);
  late final _textInput = StreamTextInput(
    active: () => mounted && widget.hasControl && _focus.hasFocus,
    send: _send,
  );
  bool _ready = false;
  bool _keyboardRequested = false;
  int? _moveFrame;
  InputGeometry? _geometry;
  Size? _viewSize;
  Offset? _panAnchor;

  void _send(Uint8List bytes) {
    if (mounted && widget.hasControl) widget.session.sendControl(bytes);
  }

  @override
  void initState() {
    super.initState();
    _attachController();
    widget.session.videoStream.addListener(_syncStream);
    unawaited(_initialize());
  }

  void _attachController() {
    assert(
      widget.controller?._state == null,
      'Use one controller per DeviceStream',
    );
    widget.controller?._state = this;
  }

  Future<void> _initialize() async {
    await _renderer.initialize();
    if (!mounted) {
      await _renderer.dispose();
      return;
    }
    _ready = true;
    _syncStream();
    setState(() {});
  }

  void _syncStream() {
    _pointers.cancel();
    _geometry = null;
    if (_ready) _renderer.srcObject = widget.session.videoStream.value;
  }

  @override
  void didUpdateWidget(DeviceStream oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._state = null;
      _attachController();
    }
    if (!widget.hasControl || oldWidget.session != widget.session) {
      _pointers.reset();
      _textInput.close();
      _keyboardRequested = false;
      _panAnchor = null;
    }
    if (oldWidget.session != widget.session) {
      oldWidget.session.videoStream.removeListener(_syncStream);
      widget.session.videoStream.addListener(_syncStream);
      _syncStream();
    }
    if (widget.hasControl && !oldWidget.hasControl && _focus.hasFocus) {
      _textInput.attach();
    }
  }

  void _updateGeometry(Size size) {
    final value = _renderer.value;
    final next =
        _ready &&
            _renderer.srcObject != null &&
            value.width > 0 &&
            value.height > 0
        ? InputGeometry(
            size,
            value.width.toInt(),
            value.height.toInt(),
            rotation: value.rotation,
          )
        : null;
    if (_viewSize != size ||
        next?.videoWidth != _geometry?.videoWidth ||
        next?.videoHeight != _geometry?.videoHeight ||
        next?.rect != _geometry?.rect) {
      _pointers.cancel();
    }
    _viewSize = size;
    _geometry = next;
  }

  void _focusChanged(bool focused) {
    if (focused && widget.hasControl) {
      _textInput.attach(show: _keyboardRequested);
    } else {
      _pointers.cancel();
      _textInput.close();
      _keyboardRequested = false;
    }
  }

  void _showKeyboard() {
    if (!widget.hasControl) return;
    _keyboardRequested = true;
    _focus.requestFocus();
    if (_focus.hasFocus) _textInput.attach(show: true);
  }

  void _down(PointerDownEvent event) {
    if (!widget.hasControl || _geometry == null) return;
    final mouse =
        event.kind == PointerDeviceKind.mouse ||
        event.kind == PointerDeviceKind.trackpad;
    if (mouse && event.buttons & kPrimaryMouseButton == 0) return;
    if (_pointers.down(
      event.pointer,
      event.localPosition,
      _geometry!,
      mouse: mouse,
    )) {
      _focus.requestFocus();
    }
  }

  void _move(PointerMoveEvent event) {
    if (!widget.hasControl) return;
    _pointers.move(event.pointer, event.localPosition);
    _moveFrame ??= SchedulerBinding.instance.scheduleFrameCallback((_) {
      _moveFrame = null;
      if (mounted && widget.hasControl) _pointers.flushMoves();
    });
  }

  void _hover(PointerHoverEvent event) {
    if (!widget.hasControl || event.buttons != 0) return;
    final geometry = _geometry;
    final point = geometry?.map(event.localPosition);
    if (point == null) return;
    widget.session.sendHover(
      encodeHover(
        videoWidth: geometry!.videoWidth,
        videoHeight: geometry.videoHeight,
        x: point.dx,
        y: point.dy,
        buttons: event.buttons,
      ),
    );
  }

  void _scroll(Offset position, Offset delta, {int buttons = 0}) {
    if (!widget.hasControl) return;
    final geometry = _geometry;
    final point = geometry?.map(position);
    if (point == null) return;
    final ticks = scrollTicks(delta);
    _send(
      encodeScroll(
        videoWidth: geometry!.videoWidth,
        videoHeight: geometry.videoHeight,
        x: point.dx,
        y: point.dy,
        hscrollTicks: ticks.dx,
        vscrollTicks: ticks.dy,
        buttons: buttons,
      ),
    );
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (!widget.hasControl) return KeyEventResult.ignored;
    // The host OS back action belongs to the embedding application.
    if (event.logicalKey == LogicalKeyboardKey.goBack) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    final code = physicalKeyCodes[event.physicalKey.usbHidUsage];
    final route = routeKey(
      code: code,
      text: event.character,
      down: event is! KeyUpEvent,
      send: _send,
      shift: keyboard.isShiftPressed,
      control: keyboard.isControlPressed,
      alt: keyboard.isAltPressed,
      meta: keyboard.isMetaPressed,
      capsLock: keyboard.lockModesEnabled.contains(KeyboardLockMode.capsLock),
    );
    if (route == KeyRoute.paste) unawaited(_paste());
    return route == KeyRoute.ignored
        ? KeyEventResult.ignored
        : KeyEventResult.handled;
  }

  Future<void> _paste() async {
    final session = widget.session;
    try {
      final text = (await Clipboard.getData('text/plain'))?.text;
      if (mounted &&
          widget.session == session &&
          widget.hasControl &&
          _focus.hasFocus &&
          text != null &&
          text.isNotEmpty) {
        _send(encodeSetClipboard(text: text, paste: true));
      }
    } on PlatformException {
      // Clipboard may be unavailable or denied by the host platform.
    }
  }

  @override
  void dispose() {
    widget.controller?._state = null;
    widget.session.videoStream.removeListener(_syncStream);
    _pointers.cancel();
    if (_moveFrame != null) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(_moveFrame!);
    }
    _textInput.close();
    _focus.dispose();
    if (_ready) unawaited(_renderer.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    autofocus: widget.autofocus,
    onFocusChange: _focusChanged,
    onKeyEvent: _key,
    child: LayoutBuilder(
      builder: (context, constraints) => ListenableBuilder(
        listenable: _renderer,
        builder: (context, _) {
          _updateGeometry(constraints.biggest);
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: (event) => _pointers.up(event.pointer),
            onPointerCancel: (event) =>
                _pointers.up(event.pointer, cancelled: true),
            onPointerHover: _hover,
            onPointerSignal: (event) {
              if (widget.hasControl &&
                  event is PointerScrollEvent &&
                  _geometry?.map(event.localPosition) != null) {
                GestureBinding.instance.pointerSignalResolver.register(event, (
                  signal,
                ) {
                  _scroll(
                    event.localPosition,
                    event.scrollDelta,
                    buttons: event.buttons,
                  );
                });
              }
              // Inertia cancellation carries no delta to inject.
              if (event is PointerScrollInertiaCancelEvent) _panAnchor = null;
            },
            onPointerPanZoomStart: (event) => _panAnchor = event.localPosition,
            onPointerPanZoomUpdate: (event) {
              final anchor = _panAnchor;
              if (anchor != null) _scroll(anchor, -event.panDelta);
            },
            onPointerPanZoomEnd: (_) => _panAnchor = null,
            child: _ready && _renderer.srcObject != null
                ? RTCVideoView(
                    _renderer,
                    objectFit:
                        RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                  )
                : const SizedBox.expand(),
          );
        },
      ),
    ),
  );
}
