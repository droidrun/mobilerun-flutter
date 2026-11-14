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
  PointerInput(this.send);
  final void Function(Uint8List) send;
  final _active = <int, _Pointer>{};

  bool contains(int id) => _active.containsKey(id);

  bool down(
    int id,
    Offset position,
    InputGeometry geometry, {
    bool mouse = false,
  }) {
    if (_active.containsKey(id)) return false;
    final point = geometry.map(position);
    if (point == null) return false;
    final used = _active.values.map((p) => p.slot).toSet();
    final free = mouse ? [-1] : List.generate(10, (i) => i);
    final slots = free.where((i) => !used.contains(i));
    if (slots.isEmpty) return false;
    final pointer = _Pointer(slots.first, point, geometry);
    _active[id] = pointer;
    _emit(AndroidMotionEvent.actionDown, pointer);
    return true;
  }

  void move(int id, Offset position) {
    final pointer = _active[id];
    if (pointer == null) return;
    final point = pointer.geometry.map(position);
    if (point == null) return;
    pointer.point = point;
    pointer.pending = true;
  }

  void flushMoves() {
    for (final pointer in _active.values) {
      if (!pointer.pending) continue;
      pointer.pending = false;
      _emit(AndroidMotionEvent.actionMove, pointer);
    }
  }

  void up(int id, {bool cancelled = false}) {
    final pointer = _active.remove(id);
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
      up(id, cancelled: true);
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
