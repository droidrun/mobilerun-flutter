// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

// Preserve public parameter names in API documentation.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'pending_approval.dart';

/// A backend decision request; no credentials or API keys belong here.
final class TaskApprovalRequest {
  /// Creates a request.
  @internal
  const TaskApprovalRequest({
    required this.taskId,
    required this.approvalId,
    required this.decision,
  });

  /// Task being decided.
  final String taskId;

  /// Approval being decided.
  final String approvalId;

  /// Requested decision.
  final ApprovalDecision decision;
}

/// Immutable state exposed by [TaskApprovalController].
final class TaskApprovalState {
  /// Creates a state snapshot.
  @internal
  const TaskApprovalState({
    this.approval,
    this.isLoading = false,
    this.isDeciding = false,
    this.decision,
    this.error,
  });

  /// The backend's pending approval, or null.
  final PendingApproval? approval;

  /// True until the initial fetch settles.
  final bool isLoading;

  /// A decision is in flight.
  final bool isDeciding;

  /// In-flight or last decision.
  final ApprovalDecision? decision;

  /// Decision errors take precedence over fetch errors.
  final Object? error;

  /// Copies a snapshot; clear flags explicitly remove nullable fields.
  TaskApprovalState _copyWith({
    PendingApproval? approval,
    bool? isLoading,
    bool? isDeciding,
    ApprovalDecision? decision,
    Object? error,
    bool clearApproval = false,
    bool clearDecision = false,
    bool clearError = false,
  }) => TaskApprovalState(
    approval: clearApproval ? null : approval ?? this.approval,
    isLoading: isLoading ?? this.isLoading,
    isDeciding: isDeciding ?? this.isDeciding,
    decision: clearDecision ? null : decision ?? this.decision,
    error: clearError ? null : error ?? this.error,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskApprovalState &&
          other.approval == approval &&
          other.isLoading == isLoading &&
          other.isDeciding == isDeciding &&
          other.decision == decision &&
          other.error == error;

  @override
  int get hashCode =>
      Object.hashAll([approval, isLoading, isDeciding, decision, error]);
}

/// Removes an integrator's push subscription.
typedef ApprovalUnsubscribe = FutureOr<void> Function();

/// Subscribes to change hints. The backend fetch remains the source of truth.
typedef ApprovalSubscribe = FutureOr<ApprovalUnsubscribe> Function(
  String taskId,
  VoidCallback onChange,
);

/// Loads approvals and forwards decisions through integrator callbacks.
///
/// Starts immediately, polls every three seconds without [subscribe] or when subscribing fails,
/// ignores stale fetches and refetches after every decision, including failures.
/// All callback failures (including timeouts) are ordinary errors. Disposal
/// invalidates outstanding work without notifying listeners.
final class TaskApprovalController extends ChangeNotifier {
  /// Creates and starts a controller for [taskId].
  TaskApprovalController({
    required String? taskId,
    required Future<PendingApproval?> Function(String taskId) fetchApproval,
    required Future<void> Function(TaskApprovalRequest request) decide,
    ApprovalSubscribe? subscribe,
    FutureOr<void> Function(Object error)? onError,
    bool enabled = true,
  }) : _taskId = taskId,
       _fetch = fetchApproval,
       _sendDecision = decide,
       _subscribe = subscribe,
       _onError = onError,
       _enabled = enabled {
    _restart();
  }

  final Future<PendingApproval?> Function(String) _fetch;
  final Future<void> Function(TaskApprovalRequest) _sendDecision;
  final ApprovalSubscribe? _subscribe;
  final FutureOr<void> Function(Object)? _onError;
  String? _taskId;
  bool _enabled;
  bool _disposed = false;
  int _epoch = 0;
  int _latest = 0;
  Timer? _poll;
  ApprovalUnsubscribe? _unsubscribe;
  bool _subscriptionFailed = false;
  Object? _fetchError;
  Object? _decideError;
  TaskApprovalState _state = const TaskApprovalState();

  /// Current immutable state.
  TaskApprovalState get state => _state;

  /// Changes task or enabled state, invalidating earlier results.
  /// A null task disables fetching; omitted enabled preserves its current value.
  void update({required String? taskId, bool? enabled}) {
    enabled ??= _enabled;
    if (_disposed || (_taskId == taskId && _enabled == enabled)) return;
    _taskId = taskId;
    _enabled = enabled;
    _restart();
  }

  bool _current(int epoch) => !_disposed && epoch == _epoch;

  void _emit(TaskApprovalState state) {
    if (_disposed || _state == state) return;
    _state = state;
    notifyListeners();
  }

  Future<void> _report(Object error) async {
    if (_disposed) return;
    try {
      await _onError?.call(error);
    } on Object {
      /* An observer must never crash the app. */
    }
  }

  Future<void> _detach(ApprovalUnsubscribe? unsubscribe) async {
    try {
      await unsubscribe?.call();
    } on Object catch (error) {
      unawaited(_report(error));
    }
  }

  void _restart() {
    final epoch = ++_epoch;
    _latest++;
    _subscriptionFailed = false;
    _poll?.cancel();
    final unsubscribe = _unsubscribe;
    _unsubscribe = null;
    _fetchError = _decideError = null;
    _emit(
      TaskApprovalState(isLoading: _enabled && (_taskId?.isNotEmpty ?? false)),
    );
    unawaited(_detach(unsubscribe));
    if (!_enabled || (_taskId?.isEmpty ?? true)) return;
    unawaited(refetch());
    if (_subscribe != null) unawaited(_attach(epoch));
  }

  Future<void> _attach(int epoch) async {
    try {
      final unsubscribe = await _subscribe!(_taskId!, () {
        if (_current(epoch)) unawaited(refetch());
      });
      if (_current(epoch)) {
        _unsubscribe = unsubscribe;
      } else {
        await _detach(unsubscribe);
      }
    } on Object catch (error) {
      if (!_current(epoch)) return;
      _subscriptionFailed = true;
      _schedulePoll();
      _fetchError = error;
      _emit(_state._copyWith(error: _decideError ?? error));
      unawaited(_report(error));
    }
  }

  /// Reloads without resubscribing. Only the newest fetch may publish a result.
  Future<void> refetch() async {
    if (_disposed || !_enabled || (_taskId?.isEmpty ?? true)) return;
    _poll?.cancel();
    final epoch = _epoch;
    final seq = ++_latest;
    bool current() => _current(epoch) && seq == _latest;
    try {
      final next = await _fetch(_taskId!);
      if (!current()) return;
      _fetchError = null;
      _emit(
        _state._copyWith(
          isLoading: false,
          approval: next,
          clearApproval: next == null,
          error: _decideError,
          clearError: _decideError == null,
        ),
      );
    } on Object catch (error) {
      if (!current()) return;
      _fetchError = error;
      _emit(_state._copyWith(isLoading: false, error: _decideError ?? error));
      unawaited(_report(error));
    } finally {
      if (current() && (_subscribe == null || _subscriptionFailed)) {
        _schedulePoll();
      }
    }
  }

  void _schedulePoll() {
    _poll?.cancel();
    _poll = Timer(const Duration(seconds: 3), () => unawaited(refetch()));
  }

  /// Sends a decision once, then refetches even when the backend rejects it.
  Future<void> decide(ApprovalDecision decision) async {
    final approval = _state.approval;
    if (_disposed || approval == null || _state.isDeciding) return;
    final epoch = _epoch;
    final taskId = _taskId;
    _decideError = null;
    _emit(
      _state._copyWith(
        isDeciding: true,
        decision: decision,
        error: _fetchError,
        clearError: _fetchError == null,
      ),
    );
    if (!_current(epoch)) return;
    try {
      await _sendDecision(
        TaskApprovalRequest(
          taskId: taskId!,
          approvalId: approval.approvalId,
          decision: decision,
        ),
      );
    } on Object catch (error) {
      if (!_current(epoch)) return;
      _decideError = error;
      unawaited(_report(error));
    } finally {
      if (_current(epoch)) {
        _emit(
          _state._copyWith(
            isDeciding: false,
            error: _decideError ?? _fetchError,
            clearError: _decideError == null && _fetchError == null,
          ),
        );
        await refetch();
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _epoch++;
    _poll?.cancel();
    unawaited(_detach(_unsubscribe));
    _unsubscribe = null;
    super.dispose();
  }
}
