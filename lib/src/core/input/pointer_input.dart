// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

// Internal input implementation; not exported by the package.
// ignore_for_file: public_member_api_docs

import 'dart:typed_data';
import 'dart:ui';

import '../../protocol/constants.dart';
import '../../protocol/control_messages.dart';
import 'input_geometry.dart';

final class _Pointer {
  _Pointer(this.slot, this.point, this.geometry);
  final int slot;
  Offset point;
  final InputGeometry geometry;
  bool pending = false;
}

/// Stable slots and one MOVE per frame per finger. Call serially on the UI thread.
final class PointerInput {
  PointerInput(this.send, {this.sendHover});
  final void Function(Uint8List) send;
  final void Function(Uint8List)? sendHover;
  final _active = <(bool, int), _Pointer>{};

  (bool, int) _identity(int id, bool mouse) => (mouse, mouse ? 0 : id);
  bool down(
    int id,
    Offset position,
    InputGeometry geometry, {
    bool mouse = false,
    int button = 0,
  }) {
    if (button != 0) return false;
    final identity = _identity(id, mouse);
    if (_active.containsKey(identity)) return false;
    final point = geometry.map(position);
    if (point == null) return false;
    final used = _active.values.map((p) => p.slot).toSet();
    final free = mouse ? [-1] : List.generate(10, (i) => i);
    final slots = free.where((i) => !used.contains(i));
    if (slots.isEmpty) return false;
    final pointer = _Pointer(slots.first, point, geometry);
    _active[identity] = pointer;
    _emit(AndroidMotionEvent.actionDown, pointer);
    return true;
  }

  void move(
    int id,
    Offset position, {
    bool mouse = false,
    InputGeometry? geometry,
    int buttons = 0,
  }) {
    final pointer = _active[_identity(id, mouse)];
    if (pointer == null) {
      if (mouse) hover(position, geometry, buttons: buttons);
      return;
    }
    final point = pointer.geometry.map(position);
    if (point == null) return;
    pointer.point = point;
    pointer.pending = true;
  }

  void hover(Offset position, InputGeometry? geometry, {int buttons = 0}) {
    final point = geometry?.map(position);
    if (point == null) return;
    sendHover?.call(
      encodeHover(
        videoWidth: geometry!.videoWidth,
        videoHeight: geometry.videoHeight,
        x: point.dx,
        y: point.dy,
        buttons: buttons,
      ),
    );
  }

  void flushMoves() {
    for (final pointer in _active.values) {
      if (!pointer.pending) continue;
      pointer.pending = false;
      _emit(AndroidMotionEvent.actionMove, pointer);
    }
  }

  void up(
    int id, {
    bool cancelled = false,
    bool mouse = false,
    int button = 0,
  }) {
    if (!cancelled && button != 0) return;
    final pointer = _active.remove(_identity(id, mouse));
    if (pointer != null) {
      _emit(
        cancelled
            ? AndroidMotionEvent.actionCancel
            : AndroidMotionEvent.actionUp,
        pointer,
      );
    }
  }

  void cancel() {
    for (final id in _active.keys.toList()) {
      up(id.$2, mouse: id.$1, cancelled: true);
    }
  }

  void _emit(int action, _Pointer pointer) => send(
    encodeTouch(
      action: action,
      pointerId: pointer.slot,
      videoWidth: pointer.geometry.videoWidth,
      videoHeight: pointer.geometry.videoHeight,
      x: pointer.point.dx,
      y: pointer.point.dy,
      pressure: 1,
      actionButton: AndroidMotionEvent.buttonPrimary,
      buttons: AndroidMotionEvent.buttonPrimary,
    ),
  );
}
