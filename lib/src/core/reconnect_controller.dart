// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'reconnect_policy.dart';
import 'scheduler.dart';

/// Where a stream is in its connect and reconnect cycle.
enum ReconnectStatus {
  /// A first attempt is in flight, or the controller is disabled.
  connecting,

  /// The peer connection is up.
  connected,

  /// An attempt failed; the next one is waiting out its backoff or running.
  reconnecting,

  /// All attempts failed; only [ReconnectController.retry] or
  /// [ReconnectController.handleWake] start a new cycle.
  unavailable,
}

/// A point-in-time view of a [ReconnectController].
final class ReconnectSnapshot {
  /// Creates a snapshot.
  const ReconnectSnapshot({required this.status, required this.attempt});

  /// The current status.
  final ReconnectStatus status;

  /// Consecutive failed attempts so far: the 1-based number of the upcoming or
  /// in-flight reconnect attempt. 0 while connecting fresh or after the
  /// stability window refilled the budget.
  final int attempt;

  @override
  bool operator ==(Object other) =>
      other is ReconnectSnapshot &&
      other.status == status &&
      other.attempt == attempt;

  @override
  int get hashCode => Object.hash(status, attempt);

  @override
  String toString() =>
      'ReconnectSnapshot(status: ${status.name}, attempt: $attempt)';
}

/// Pure reconnect state machine for a single device stream.
///
/// Lifecycle contract with the host:
///
/// * [attemptMounted] is called after every (re)mount of the stream, and on
///   enable. It arms the connect watchdog.
/// * `onRemount` asks the host to start a new attempt; the host calls
///   [attemptMounted] back once it did.
/// * [handleConnected] and [handleDisconnected] mirror the peer connection
///   state; [handleFailure] is the terminal failure signal (socket died, peer
///   connection failed, negotiation threw).
///
/// Policy: a failed attempt schedules the next one with exponential backoff
/// (1 s to 30 s, ±25 % jitter). After [ReconnectPolicy.maxAttempts]
/// consecutive failures the stream is unavailable and retries stop. Holding a
/// connection for [InternalReconnectPolicy.stability] refills the retry budget.
/// [handleWake] short-circuits a pending backoff and starts a fresh cycle when
/// unavailable.
///
/// The controller schedules everything through the injected [Scheduler] and
/// calls back synchronously from the method that caused the transition.
final class ReconnectController {
  /// Creates a controller.
  ///
  /// [onRemount] asks the host to remount the stream (start a new attempt),
  /// [onSnapshot] reports a changed status or attempt count and [onHeal] asks
  /// the host to refetch stream credentials; it is called once per recovery
  /// cycle, not per attempt, so a shared outage does not turn into a request
  /// storm. [scheduler] runs the timers and defaults to [TimerScheduler];
  /// [random] feeds the backoff jitter and defaults to a `dart:math`
  /// generator.
  ReconnectController({
    required this._onRemount,
    required this._onSnapshot,
    required this._onHeal,
    this._scheduler = const TimerScheduler(),
    this._random,
  });

  final void Function() _onRemount;
  final void Function(ReconnectSnapshot snapshot) _onSnapshot;
  final void Function() _onHeal;
  final Scheduler _scheduler;
  final double Function()? _random;

  bool _disposed = false;
  bool _enabled = false;
  ReconnectStatus _status = ReconnectStatus.connecting;
  int _attempt = 0;

  // Whether the current mount epoch ever reached connected. Gates
  // handleDisconnected: the peer connection reports non-connected states
  // during normal negotiation, which must not count as failures.
  bool _everConnectedThisEpoch = false;

  // One failure per mount epoch: a dying attempt fires several signals that
  // must collapse into a single backoff step.
  bool _failureLatched = false;

  // One heal per recovery cycle. Tracked explicitly: a fresh cycle heals with
  // the attempt reset to 0, so its first failed retry would otherwise heal
  // again at attempt 1.
  bool _healedThisCycle = false;

  ScheduledTask? _watchdogTimer;
  ScheduledTask? _backoffTimer;
  ScheduledTask? _stabilityTimer;

  /// The current status and attempt count.
  ReconnectSnapshot get snapshot =>
      ReconnectSnapshot(status: _status, attempt: _attempt);

  // A backoff wait is pending, or all attempts failed.
  bool get _waitingOrUnavailable =>
      _backoffTimer != null || _status == ReconnectStatus.unavailable;

  void _emit() => _onSnapshot(snapshot);

  static ScheduledTask? _clear(ScheduledTask? task) {
    task?.cancel();
    return null;
  }

  void _clearAllTimers() {
    _watchdogTimer = _clear(_watchdogTimer);
    _backoffTimer = _clear(_backoffTimer);
    _stabilityTimer = _clear(_stabilityTimer);
  }

  void _countFailure() {
    // A wait is already scheduled, or we already gave up (for example a stale
    // watchdog from a double mount). Never stack timers.
    if (_waitingOrUnavailable) return;
    _failureLatched = true;
    _watchdogTimer = _clear(_watchdogTimer);
    _stabilityTimer = _clear(_stabilityTimer);
    _attempt += 1;
    if (_attempt > ReconnectPolicy.maxAttempts) {
      _status = ReconnectStatus.unavailable;
      _emit();
      return;
    }
    _status = ReconnectStatus.reconnecting;
    _emit();
    if (!_healedThisCycle) {
      _healedThisCycle = true;
      _onHeal();
    }
    _backoffTimer = _scheduler.schedule(
      reconnectDelay(_attempt, random: _random),
      () {
        _backoffTimer = null;
        _onRemount();
      },
    );
  }

  void _freshCycle() {
    _attempt = 0;
    _failureLatched = false;
    _everConnectedThisEpoch = false;
    // This heal covers the whole restarted cycle: a failure of the restarted
    // attempt must not heal a second time.
    _healedThisCycle = true;
    _status = ReconnectStatus.reconnecting;
    _emit();
    _onHeal();
    _onRemount();
  }

  /// The stream (re)mounted: arms the connect watchdog.
  void attemptMounted() {
    if (_disposed) return;
    _enabled = true;
    // A mount during a wait is stale: the scheduled attempt owns the next
    // watchdog.
    if (_waitingOrUnavailable) return;
    _watchdogTimer = _clear(_watchdogTimer);
    _everConnectedThisEpoch = false;
    _failureLatched = false;
    if (_status == ReconnectStatus.connected) {
      // The remount tossed the live connection (credential rotation); the new
      // one is negotiating.
      _stabilityTimer = _clear(_stabilityTimer);
      _status = ReconnectStatus.connecting;
      _emit();
    }
    _watchdogTimer = _scheduler.schedule(
      InternalReconnectPolicy.connectTimeout,
      () {
        _watchdogTimer = null;
        _countFailure();
      },
    );
  }

  /// There is no stream target anymore: stops all timers and resets counters.
  void setDisabled() {
    if (_disposed) return;
    _enabled = false;
    _clearAllTimers();
    _everConnectedThisEpoch = false;
    _failureLatched = false;
    _healedThisCycle = false;
    if (_status != ReconnectStatus.connecting || _attempt != 0) {
      _status = ReconnectStatus.connecting;
      _attempt = 0;
      _emit();
    }
  }

  /// The peer connection reached the connected state.
  void handleConnected() {
    if (!_enabled) return;
    _watchdogTimer = _clear(_watchdogTimer);
    // The old attempt recovered on its own (a transient dip): the scheduled
    // remount would only interrupt it again.
    _backoffTimer = _clear(_backoffTimer);
    _everConnectedThisEpoch = true;
    _failureLatched = false;
    if (_status != ReconnectStatus.connected) {
      _status = ReconnectStatus.connected;
      _emit();
    }
    _stabilityTimer = _clear(_stabilityTimer);
    _stabilityTimer = _scheduler.schedule(
      InternalReconnectPolicy.stability,
      () {
        _stabilityTimer = null;
        // The cycle is over: the next failure run heals anew.
        _healedThisCycle = false;
        if (_attempt != 0) {
          _attempt = 0;
          _emit();
        }
      },
    );
  }

  /// The peer connection left the connected state. Only counts as a failure
  /// when this mount epoch had connected before.
  void handleDisconnected() {
    if (!_enabled) return;
    if (!_everConnectedThisEpoch) return;
    if (_failureLatched) return;
    _countFailure();
  }

  /// A terminal failure of the current attempt.
  void handleFailure() {
    if (!_enabled) return;
    if (_failureLatched) return;
    _countFailure();
  }

  /// Whether a stream target change (URL or token rotation) must be held back
  /// instead of applied now.
  ///
  /// True while waiting out a backoff (an immediate switch would bypass the
  /// wait; the scheduled attempt picks up the fresh target itself) and while
  /// unavailable. Everywhere else the new target applies immediately.
  bool shouldDeferTargetChange() => _waitingOrUnavailable;

  /// The app became visible or the network came back.
  void handleWake() {
    if (!_enabled) return;
    if (_status == ReconnectStatus.unavailable) {
      _freshCycle();
      return;
    }
    if (_backoffTimer != null) {
      // Don't sit out a possibly throttled background wait now that the user
      // is looking.
      _backoffTimer = _clear(_backoffTimer);
      _onRemount();
    }
  }

  /// A manual retry; only acts while unavailable.
  void retry() {
    if (!_enabled) return;
    if (_status == ReconnectStatus.unavailable) _freshCycle();
  }

  /// Stops all timers. Every method is a no-op afterwards.
  void dispose() {
    _disposed = true;
    _enabled = false;
    _clearAllTimers();
  }
}
