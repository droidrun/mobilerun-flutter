// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'package:mobilerun_flutter/src/core/scheduler.dart';

/// A fake clock starting at 0 ms. Timers fire in due-time order; timers due at
/// the same time fire in the order they were scheduled.
final class FakeScheduler implements Scheduler {
  final List<_Timer> _timers = [];
  int _sequence = 0;

  /// The current fake time in milliseconds.
  int nowMs = 0;

  @override
  Duration get now => Duration(milliseconds: nowMs);

  /// Number of timers still scheduled.
  int get pendingTimers => _timers.length;

  @override
  ScheduledTask schedule(Duration delay, void Function() callback) {
    final timer = _Timer(nowMs + delay.inMilliseconds, _sequence++, callback);
    _timers.add(timer);
    return _FakeTask(() => _timers.remove(timer));
  }

  /// Advances the clock to [targetMs], firing every timer due on the way
  /// (including those due exactly at [targetMs]).
  void advanceTo(int targetMs) {
    while (true) {
      final due = _timers.where((t) => t.dueMs <= targetMs).toList()
        ..sort((a, b) {
          final byDue = a.dueMs.compareTo(b.dueMs);
          return byDue != 0 ? byDue : a.sequence.compareTo(b.sequence);
        });
      if (due.isEmpty) break;
      final next = due.first;
      _timers.remove(next);
      if (next.dueMs > nowMs) nowMs = next.dueMs;
      next.callback();
    }
    if (targetMs > nowMs) nowMs = targetMs;
  }
}

final class _Timer {
  _Timer(this.dueMs, this.sequence, this.callback);

  final int dueMs;
  final int sequence;
  final void Function() callback;
}

final class _FakeTask implements ScheduledTask {
  _FakeTask(this._onCancel);

  final void Function() _onCancel;

  @override
  void cancel() => _onCancel();
}
