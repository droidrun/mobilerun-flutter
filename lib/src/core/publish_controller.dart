// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'publish.dart';
import 'publish_transport.dart';
import 'scheduler.dart';
import 'stream_error.dart';
import 'stream_transports.dart';

/// One publication controller per viewer session. All asynchronous work is fenced
/// by both the operation object and its original connection binding.
final class PublishController {
  /// Creates a controller without capture or signaling side effects.
  PublishController({
    required this.capabilities,
    required this.capture,
    required this.scheduler,
    required this.uuid,
    required this.onFailure,
  });

  /// First-offer configuration, never interpreted as authorization.
  final DevicePublishCapabilities? capabilities;

  /// Capture adapter.
  final PublishCapture? capture;

  /// Monotonic deadline scheduler.
  final Scheduler scheduler;

  /// Fresh media UUID producer.
  final String Function() uuid;

  /// Session's publish error observer.
  final void Function(PublishFailure, String?) onFailure;

  /// Replayable immutable snapshots.
  final state = ValueNotifier(PublishState());

  /// Local camera encoder and first-offer reservation availability for controls.
  final cameraAvailable = ValueNotifier(false);

  /// Called after the first offer has validated its reserved upstream sections.
  void reservationsReady() {
    final peer = _binding?.peer;
    cameraAvailable.value =
        peer is PublishPeerTransport &&
        (peer as PublishPeerTransport).publishKinds.contains(PublishKind.video);
  }

  _Binding? _binding;
  _Operation? _operation;
  int _generation = 0;
  Future<void> _teardown = Future.value();
  Future<void>? _release;
  bool _closed = false;

  /// Binds a new viewer's original peer and socket, before its first offer.
  void bind(PeerTransport peer, SignallingConnection socket) {
    unbind();
    _binding = _Binding(peer, socket);
  }

  /// Supplies connection readiness without disturbing same-peer ICE refreshes.
  void setConnected(SignallingConnection? socket, bool connected) {
    if (socket != _binding?.socket) return;
    _binding?.connected = connected;
    final op = _operation;
    if (!connected && op != null) {
      unawaited(
        _finish(
          op,
          failure: _failure(
            StreamErrorReason.disconnected,
            'Viewer disconnected',
          ),
        ),
      );
    }
  }

  /// Ends publication on socket/peer loss or connection replacement.
  void unbind() {
    final operation = _operation;
    _binding = null;
    cameraAvailable.value = false;
    if (operation != null) {
      unawaited(
        _finish(
          operation,
          failure: _failure(
            StreamErrorReason.disconnected,
            'Viewer disconnected',
          ),
        ),
      );
    }
  }

  /// Cancels publication on session close, silencing later observers.
  Future<void> close() async {
    _closed = true;
    await stop();
    _binding = null;
  }

  PublishFailure _failure(
    StreamErrorReason reason,
    String message, [
    String? detail,
  ]) => PublishFailure(reason: reason, message: message, detail: detail);

  bool _current(_Operation op) =>
      identical(_operation, op) && identical(_binding, op.binding) && !_closed;

  /// Starts exactly one atomic publication and resolves only on full activation.
  Future<PublishState> start(PublishOptions options) {
    final current = _operation;
    PublishFailure? failure;
    final binding = _binding;
    final caps = capabilities;
    final peer = binding?.peer;
    final kinds = [PublishKind.audio, if (options.video) PublishKind.video];
    if (current != null) {
      failure = _failure(
        StreamErrorReason.publishFailed,
        'Publication already in progress',
        state.value.phase == PublishPhase.active
            ? 'already_publishing'
            : 'publish_in_progress',
      );
    } else if (_closed) {
      failure = _failure(
        StreamErrorReason.disconnected,
        'Session is closed',
        'session_closed',
      );
    } else if (!options.audio) {
      failure = _failure(
        StreamErrorReason.publishFailed,
        'Audio is required',
        'invalid_options',
      );
    } else if (caps == null) {
      failure = _failure(
        StreamErrorReason.publishUnsupported,
        'Publish capabilities unavailable',
        'capabilities_unavailable',
      );
    } else if (!caps.supportsMicrophone ||
        (options.video && !caps.cameraInjection)) {
      failure = _failure(
        StreamErrorReason.publishUnsupported,
        'Device input unsupported',
        'device_capability',
      );
    } else if (binding == null || !binding.connected) {
      failure = _failure(
        StreamErrorReason.disconnected,
        'Viewer is not connected',
        'not_connected',
      );
    } else if (capture == null ||
        peer is! PublishPeerTransport ||
        !kinds.every((peer as PublishPeerTransport).publishKinds.contains)) {
      failure = _failure(
        StreamErrorReason.publishUnsupported,
        'Local media unsupported',
        'local_media_support',
      );
    }
    if (failure != null) {
      // A concurrent call must leave the existing operation and state untouched.
      if (current == null && !_closed) {
        _generation++;
        state.value = PublishState(
          phase: PublishPhase.error,
          kinds: kinds,
          reason: failure.reason.code,
          message: failure.message,
          detail: failure.detail,
        );
      }
      if (!_closed) onFailure(failure, null);
      return Future.error(PublishException(failure));
    }
    final operation = _Operation(binding!, kinds, ++_generation);
    _operation = operation;
    unawaited(_capture(operation, options));
    return operation.result.future;
  }

  void _snapshot(
    _Operation op,
    PublishPhase phase, {
    PublishFailure? failure,
    String? reason,
  }) {
    if (_closed) return;
    state.value = PublishState(
      phase: phase,
      mediaSessionId: op.id,
      kinds: op.kinds,
      reason: reason ?? failure?.reason.code,
      message: failure?.message,
      detail: failure?.detail,
      serverReason: failure?.serverReason,
    );
  }

  Future<void> _capture(_Operation op, PublishOptions options) async {
    await _teardown;
    if (!_current(op)) return;
    _snapshot(op, PublishPhase.capturing);
    // State listeners may synchronously cancel or close the session.
    if (!_current(op)) return;
    try {
      final media = await capture!.capture(
        options,
        isCancelled: () => !_current(op),
        onAcquired: (media) {
          if (_current(op)) {
            op.media = media;
          } else {
            unawaited(media.stop());
          }
        },
      );
      if (!_current(op)) {
        await media.stop();
        return;
      }
      op.media = media;
      for (final track in media.tracks) {
        track.onEnded = () {
          if (_current(op)) {
            unawaited(
              _finish(
                op,
                failure: _failure(
                  StreamErrorReason.publishFailed,
                  'Local input ended',
                  'capture_unavailable',
                ),
              ),
            );
          }
        };
      }
      if (!op.kinds.every(
        (kind) => media.tracks.any((track) => track.kind == kind.name),
      )) {
        await _finish(
          op,
          failure: _failure(
            StreamErrorReason.publishFailed,
            'Local input unavailable',
            'capture_unavailable',
          ),
        );
        return;
      }
      op.id = uuid();
      _snapshot(op, PublishPhase.starting);
      if (!_current(op)) return;
      op.timer = scheduler.schedule(const Duration(seconds: 5), () {
        if (_current(op)) {
          unawaited(
            _finish(
              op,
              failure: _failure(
                StreamErrorReason.publishUnsupported,
                'Publish response timed out',
                'response_timeout',
              ),
            ),
          );
        }
      });
      op.sent = true;
      op.binding.socket.send(
        jsonEncode({
          'type': 'publishStart',
          'mediaSessionId': op.id,
          'kinds': op.kinds.map((kind) => kind.name).toList(),
        }),
      );
    } on Object catch (error) {
      if (!_current(op)) return;
      await _finish(
        op,
        failure: error is PublishException
            ? error.failure
            : _failure(
                op.sent
                    ? StreamErrorReason.disconnected
                    : StreamErrorReason.publishFailed,
                op.sent ? 'Signaling unavailable' : 'Local input unavailable',
                op.sent ? null : 'capture_unavailable',
              ),
      );
    }
  }

  /// Handles only valid, correlated publication frames from the original socket.
  void receive(SignallingConnection socket, String text) {
    final op = _operation;
    if (op == null ||
        !_current(op) ||
        !identical(socket, op.binding.socket) ||
        op.id == null) {
      return;
    }
    final Object? value;
    try {
      value = jsonDecode(text);
    } on FormatException {
      return;
    }
    if (value is! Map ||
        value['type'] != 'publishState' ||
        value['mediaSessionId'] is! String ||
        value['mediaSessionId'] != op.id) {
      return;
    }
    final phase = value['state'];
    if (phase != 'accepted' &&
        phase != 'active' &&
        phase != 'stopped' &&
        phase != 'rejected' &&
        phase != 'error') {
      return;
    }
    if (phase == 'accepted' || phase == 'active') {
      if (phase == 'active') op.active = true;
      if (!op.accepted) {
        op.accepted = true;
        op.timer?.cancel();
        if (!op.active) {
          op.timer = scheduler.schedule(const Duration(seconds: 15), () {
            if (_current(op)) {
              unawaited(
                _finish(
                  op,
                  failure: _failure(
                    StreamErrorReason.publishTimeout,
                    'Publish activation timed out',
                    'active_timeout',
                  ),
                ),
              );
            }
          });
        }
        _snapshot(op, PublishPhase.accepted);
        if (!_current(op)) return;
        op.mutations = _attach(op);
      }
      if (op.active) op.timer?.cancel();
      _activate(op);
      return;
    }
    final reason = value['reason'] is String ? value['reason'] as String : null;
    final normalized = switch (reason) {
      'forbidden' => StreamErrorReason.publishNotAllowed,
      'unsupported' => StreamErrorReason.publishUnsupported,
      'busy' => StreamErrorReason.publishBusy,
      'connection_closed' => StreamErrorReason.disconnected,
      _ => StreamErrorReason.publishFailed,
    };
    unawaited(
      _finish(
        op,
        failure: PublishFailure(
          reason: normalized,
          message: 'Publication ended: ${normalized.code}',
          serverReason: reason,
          detail: reason == 'stopped_by_client' ? 'remote_stop' : null,
        ),
      ),
    );
  }

  Future<void> _attach(_Operation op) async {
    final peer = op.binding.peer as PublishPeerTransport;
    try {
      final usable = await peer.canAttachPublish(op.kinds);
      if (!_current(op)) return;
      if (!usable) {
        // Do not await cleanup from inside the mutation cleanup itself awaits.
        unawaited(
          _finish(
            op,
            failure: _failure(
              StreamErrorReason.publishUnsupported,
              'Reserved sender unavailable',
              'negotiated_sender',
            ),
          ),
        );
        return;
      }
      for (final kind in op.kinds) {
        if (!_current(op)) return;
        final track = op.media!.tracks.firstWhere(
          (track) => track.kind == kind.name,
        );
        await peer.replacePublishTrack(kind, track);
        if (!_current(op)) {
          await track.stop();
          await peer.replacePublishTrack(kind, null);
          return;
        }
      }
      op.attached = true;
      _activate(op);
    } on Object {
      if (_current(op)) {
        unawaited(
          _finish(
            op,
            failure: _failure(
              StreamErrorReason.publishFailed,
              'Could not attach local input',
              'attach_failed',
            ),
          ),
        );
      }
    }
  }

  void _activate(_Operation op) {
    if (!_current(op) || !op.active || !op.attached || op.result.isCompleted) {
      return;
    }
    _snapshot(op, PublishPhase.active);
    if (_current(op)) op.result.complete(state.value);
  }

  /// Idempotent explicit stop; never waits for a server acknowledgement.
  Future<void> stop() {
    final op = _operation;
    return op == null ? (_release ?? Future.value()) : _finish(op);
  }

  Future<void> _finish(_Operation op, {PublishFailure? failure}) {
    if (!identical(_operation, op)) return _release ?? Future.value();
    _operation = null; // Fence capture, attachment, frames and timers first.
    op.timer?.cancel();
    for (final track in op.media?.tracks ?? const []) {
      track.onEnded = null;
    }
    if (op.sent) {
      try {
        op.binding.socket.send(
          jsonEncode({'type': 'stopPublish', 'mediaSessionId': op.id}),
        );
      } on Object {
        /* Best effort, original socket only. */
      }
    }
    // Stop capture immediately, independently of a slow sender or closed peer.
    final releasing = _stopMedia(op);
    final previousTeardown = _teardown;
    _teardown = () async {
      await previousTeardown;
      await _cleanup(op, releasing);
    }();
    unawaited(
      _teardown.then((_) {
        // A replacement operation owns the state now; never overwrite it.
        if (op.generation == _generation) {
          _snapshot(
            op,
            failure == null ? PublishPhase.stopped : PublishPhase.error,
            failure: failure,
            reason: failure == null ? 'stopped_by_client' : null,
          );
        }
        if (failure != null && !_closed) onFailure(failure, op.id);
        if (!op.result.isCompleted) {
          op.result.completeError(
            PublishException(
              failure ??
                  _failure(
                    StreamErrorReason.publishCancelled,
                    'Publication cancelled',
                  ),
            ),
          );
        }
      }),
    );
    _release = _teardown;
    return _teardown;
  }

  Future<void> _stopMedia(_Operation op) async {
    try {
      await op.media?.stop();
    } on Object {
      /* Continue terminal delivery. */
    }
  }

  Future<void> _cleanup(_Operation op, Future<void> releasing) async {
    try {
      await releasing;
    } on Object {
      /* Continue detaching. */
    }
    try {
      await op.mutations;
    } on Object {
      /* Continue detaching. */
    }
    final peer = op.binding.peer;
    if (peer is PublishPeerTransport) {
      for (final kind in op.kinds) {
        try {
          await (peer as PublishPeerTransport).replacePublishTrack(kind, null);
        } on Object {
          /* Closed peer. */
        }
      }
    }
  }
}

final class _Binding {
  _Binding(this.peer, this.socket);
  final PeerTransport peer;
  final SignallingConnection socket;
  bool connected = false;
}

final class _Operation {
  _Operation(this.binding, this.kinds, this.generation);
  final int generation;
  final _Binding binding;
  final List<PublishKind> kinds;
  final result = Completer<PublishState>();
  String? id;
  PublishMedia? media;
  ScheduledTask? timer;
  bool sent = false, accepted = false, active = false, attached = false;
  Future<void> mutations = Future.value();
}
