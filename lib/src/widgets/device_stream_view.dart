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

/// Optional handle for one mounted [DeviceStreamView]. Calls while detached are
/// no-ops; input also requires the view's `hasControl` to be true.
final class DeviceStreamController {
  _DeviceStreamViewState? _state;

  /// Focuses the view and opens the platform keyboard.
  void showKeyboard() => _state?._showKeyboard();

  /// Finalizes composition and closes the keyboard when this view owns input.
  /// A host editor's keyboard is left alone.
  void hideKeyboard() => _state?._hideKeyboard();

  /// Sends one DOWN/UP pair for an explicit navigation action.
  void sendSystemKey(DeviceSystemKey key) {
    final state = _state;
    if (state != null) {
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
class DeviceStreamView extends StatefulWidget {
  /// Creates a live video and input view.
  const DeviceStreamView({
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

  /// Optional handle. The most recently mounted view takes ownership.
  final DeviceStreamController? controller;

  /// Whether to request hardware-key focus when mounted.
  final bool autofocus;

  @override
  State<DeviceStreamView> createState() => _DeviceStreamViewState();
}

class _DeviceStreamViewState extends State<DeviceStreamView> {
  final _renderer = RTCVideoRenderer();
  final _focus = FocusNode(debugLabel: 'DeviceStreamView');
  late var _pointers = PointerInput(
    widget.session.sendControl,
    sendHover: widget.session.sendHover,
  );
  late final _textInput = StreamTextInput(
    active: () => mounted && widget.hasControl && _focus.hasFocus,
    send: _send,
  );
  bool _ready = false;
  bool _keyboardRequested = false;
  int? _moveFrame;
  InputGeometry? _geometry;
  final _keys = KeyInput();
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
  void didUpdateWidget(DeviceStreamView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller?._state == this) {
        oldWidget.controller?._state = null;
      }
      _attachController();
    }
    final lostControl = oldWidget.hasControl && !widget.hasControl;
    final sessionChanged = oldWidget.session != widget.session;
    if (lostControl || sessionChanged) {
      // The pointer sender is bound to the session that received DOWN.
      _pointers.cancel();
      _textInput.close();
      _keys.clear();
      _keyboardRequested = false;
      _panAnchor = null;
    }
    if (sessionChanged) {
      oldWidget.session.videoStream.removeListener(_syncStream);
      _pointers = PointerInput(
        widget.session.sendControl,
        sendHover: widget.session.sendHover,
      );
      widget.session.videoStream.addListener(_syncStream);
      _syncStream();
    }
    if (sessionChanged || !oldWidget.hasControl && widget.hasControl) {
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
    if ((next?.rect, next?.videoWidth, next?.videoHeight) !=
        (_geometry?.rect, _geometry?.videoWidth, _geometry?.videoHeight)) {
      _pointers.cancel();
    }
    _geometry = next;
  }

  void _focusChanged(bool focused) {
    if (focused) {
      _textInput.attach(show: _keyboardRequested);
    } else {
      _pointers.cancel();
      _textInput.close();
      _keys.clear();
      _keyboardRequested = false;
    }
  }

  void _showKeyboard() {
    if (!widget.hasControl) return;
    _keyboardRequested = true;
    _focus.requestFocus();
    _textInput.attach(show: true);
  }

  void _hideKeyboard() {
    _keyboardRequested = false;
    _textInput.hide();
  }

  void _down(PointerDownEvent event) {
    if (!widget.hasControl || _geometry == null) return;
    final mouse = _isMouse(event);
    if (_pointers.down(
      event.pointer,
      event.localPosition,
      _geometry!,
      mouse: mouse,
      button: mouse && event.buttons & kPrimaryMouseButton == 0 ? 1 : 0,
    )) {
      _focus.requestFocus();
    }
  }

  void _move(PointerMoveEvent event) {
    if (!widget.hasControl) return;
    _pointers.move(
      event.pointer,
      event.localPosition,
      mouse: _isMouse(event),
      geometry: _geometry,
      buttons: event.buttons,
    );
    _moveFrame ??= SchedulerBinding.instance.scheduleFrameCallback((_) {
      _moveFrame = null;
      if (mounted && widget.hasControl) _pointers.flushMoves();
    });
  }

  void _hover(PointerEvent event) {
    if (!widget.hasControl) return;
    _pointers.hover(event.localPosition, _geometry, buttons: event.buttons);
  }

  void _scroll(Offset position, Offset delta, {int buttons = 0}) {
    if (!widget.hasControl) return;
    final geometry = _geometry;
    if (geometry == null) return;
    routeScroll(
      geometry: geometry,
      position: position,
      ticks: scrollTicks(delta),
      send: _send,
      buttons: buttons,
    );
  }

  bool _isMouse(PointerEvent event) =>
      event.kind == PointerDeviceKind.mouse ||
      event.kind == PointerDeviceKind.trackpad;

  void _signal(PointerSignalEvent event) {
    if (widget.hasControl &&
        event is PointerScrollEvent &&
        _geometry?.map(event.localPosition) != null) {
      GestureBinding.instance.pointerSignalResolver.register(event, (_) {
        _scroll(event.localPosition, event.scrollDelta, buttons: event.buttons);
      });
    }
    if (event is PointerScrollInertiaCancelEvent) _panAnchor = null;
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (!widget.hasControl) return KeyEventResult.ignored;
    // The host OS back action belongs to the embedding application.
    if (event.logicalKey == LogicalKeyboardKey.goBack) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    final code =
        physicalKeyCodes[event.physicalKey.usbHidUsage] ??
        logicalKeyCodes[event.logicalKey.keyId];
    final down = event is! KeyUpEvent;
    final raw = event.character;
    final character = raw != null && raw.runes.every(isPrintableRune)
        ? raw
        : null;
    // Native Ctrl combinations may omit the produced character or report a
    // C0 control. Recover the layout-aware logical key, never the physical code.
    final produced =
        (keyboard.isControlPressed || keyboard.isMetaPressed) &&
            (character == null || !character.runes.every(isPrintableRune))
        ? event.logicalKey.keyLabel
        : character;
    final route = _keys.route(
      code: code,
      text: produced,
      down: down,
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
    if (widget.controller?._state == this) widget.controller?._state = null;
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
          return RawGestureDetector(
            gestures: {
              _DeviceGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    _DeviceGestureRecognizer
                  >(
                    _DeviceGestureRecognizer.new,
                    (recognizer) => recognizer.accepts = (position) =>
                        widget.hasControl && _geometry?.map(position) != null,
                  ),
            },
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _down,
              onPointerMove: _move,
              onPointerUp: (event) =>
                  _pointers.up(event.pointer, mouse: _isMouse(event)),
              onPointerCancel: (event) => _pointers.up(
                event.pointer,
                mouse: _isMouse(event),
                cancelled: true,
              ),
              onPointerHover: _hover,
              onPointerSignal: _signal,
              onPointerPanZoomStart: (event) =>
                  _panAnchor = event.localPosition,
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
            ),
          );
        },
      ),
    ),
  );
}

// Claim only the video interaction, leaving letterboxes and display-only
// views available to ancestor scrolling and navigation gestures.
class _DeviceGestureRecognizer extends EagerGestureRecognizer {
  late bool Function(Offset) accepts;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (accepts(event.localPosition)) super.addAllowedPointer(event);
  }

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    if (!accepts(event.localPosition)) return;
    startTrackingPointer(event.pointer, event.transform);
    resolve(GestureDisposition.accepted);
    stopTrackingPointer(event.pointer);
  }
}
