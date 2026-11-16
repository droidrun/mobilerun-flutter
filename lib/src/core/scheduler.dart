// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

/// A scheduled callback that can be cancelled.
abstract interface class ScheduledTask {
  /// Cancels the callback if it has not fired yet.
  void cancel();
}

/// Runs callbacks after a delay. Stream components schedule through this
/// interface so tests can supply a fake clock.
abstract interface class Scheduler {
  /// Monotonic time for measuring durations on this clock.
  Duration get now;

  /// Runs [callback] once after [delay].
  ScheduledTask schedule(Duration delay, void Function() callback);
}

/// A [Scheduler] backed by `dart:async` timers.
final class TimerScheduler implements Scheduler {
  /// Creates a scheduler on the current zone's timers.
  const TimerScheduler();

  static final _clock = Stopwatch()..start();

  @override
  Duration get now => _clock.elapsed;

  @override
  ScheduledTask schedule(Duration delay, void Function() callback) =>
      _TimerTask(Timer(delay, callback));
}

final class _TimerTask implements ScheduledTask {
  _TimerTask(this._timer);

  final Timer _timer;

  @override
  void cancel() => _timer.cancel();
}
