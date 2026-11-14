// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';

import 'package:mobilerun_flutter/mobilerun_flutter.dart';

/// Wraps the default signalling connector with debug hooks for the scripted
/// run: forcing the socket closed and replaying an `rtcConfiguration` refresh,
/// which the server only pushes when TURN credentials are about to expire.
final class DebugSignalling implements SignallingConnector {
  DebugSignalling([this._inner = const WebSocketSignallingConnector()]);

  final SignallingConnector _inner;
  _DebugConnection? _current;

  /// Frame types the client sent over the current socket, in order.
  List<String> get sentTypes => _current?.sentTypes ?? const [];

  /// Closes the signalling socket as if the network dropped it.
  void killSocket() => unawaited(_current?._inner.close());

  /// Delivers the last `rtcConfiguration` again as if the server had
  /// refreshed the credentials. Returns false when none was seen yet.
  bool injectRefresh() => _current?.injectRefresh() ?? false;

  @override
  Future<SignallingConnection> connect(Uri uri) async {
    final connection = _DebugConnection(await _inner.connect(uri));
    _current = connection;
    return connection;
  }
}

final class _DebugConnection implements SignallingConnection {
  _DebugConnection(this._inner) {
    _out = StreamController<String>(
      onListen: () {
        _subscription = _inner.messages.listen(
          (frame) {
            _remember(frame);
            _out.add(frame);
          },
          onError: _out.addError,
          onDone: _out.close,
        );
      },
      onCancel: () => _subscription?.cancel(),
    );
  }

  final SignallingConnection _inner;
  late final StreamController<String> _out;
  StreamSubscription<String>? _subscription;
  String? _lastConfiguration;
  final List<String> sentTypes = [];

  void _remember(String frame) {
    try {
      final json = jsonDecode(frame);
      if (json is Map && json['type'] == 'rtcConfiguration') {
        _lastConfiguration = frame;
      }
    } on FormatException {
      // Not JSON: the session decides what to do with it.
    }
  }

  bool injectRefresh() {
    final frame = _lastConfiguration;
    if (frame == null || _out.isClosed) return false;
    _out.add(frame);
    return true;
  }

  @override
  Stream<String> get messages => _out.stream;

  @override
  void send(String frame) {
    sentTypes.add((jsonDecode(frame) as Map)['type']! as String);
    _inner.send(frame);
  }

  @override
  Future<void> close() => _inner.close();
}
