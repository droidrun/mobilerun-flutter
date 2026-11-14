// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';

// The scripted run wraps the default transports, which are not public API.
// ignore_for_file: implementation_imports
import 'package:mobilerun_flutter/mobilerun_flutter.dart' show StreamConfig;
import 'package:mobilerun_flutter/src/core/stream_transports.dart';
import 'package:mobilerun_flutter/src/webrtc/default_transports.dart';

/// The default transports with debug hooks for the scripted run: forcing the
/// signalling socket closed, replaying an `rtcConfiguration` refresh (the
/// server only pushes one when TURN credentials are about to expire), and
/// recording what went over the wire.
final class DebugTransports {
  DebugTransports() {
    final defaults = defaultStreamTransports();
    signalling = DebugSignalling(defaults.signalling);
    peers = DebugPeers(defaults.peers);
  }

  late final DebugSignalling signalling;
  late final DebugPeers peers;

  StreamTransports get transports =>
      StreamTransports(signalling: signalling, peers: peers);

  /// Frame types the client sent on the current socket, in order.
  List<String> get sent => signalling.sent;

  /// Frame types received on the current socket, in order.
  List<String> get received => signalling.received;

  /// The local `a=ice-ufrag` of every offer sent on the current socket.
  List<String> get offerUfrags => signalling.offerUfrags;

  /// Closes the signalling socket as if the network dropped it.
  void killSocket() => unawaited(signalling.current?.inner.close());

  /// Delivers the last `rtcConfiguration` again as if the server refreshed the
  /// credentials. Returns false when none was seen yet.
  bool injectRefresh() => signalling.current?.injectRefresh() ?? false;

  /// Frames decoded so far on the current peer connection, or null.
  Future<int?> framesDecoded() async =>
      (await peers.last?.readVideoStats())?.framesDecoded;
}

final class DebugSignalling implements SignallingConnector {
  DebugSignalling(this._inner);

  final SignallingConnector _inner;
  DebugConnection? current;

  List<String> get sent => current?.sent ?? const [];
  List<String> get received => current?.received ?? const [];
  List<String> get offerUfrags => current?.offerUfrags ?? const [];

  @override
  Future<SignallingConnection> connect(Uri uri) async {
    final connection = DebugConnection(await _inner.connect(uri));
    current = connection;
    return connection;
  }
}

final class DebugConnection implements SignallingConnection {
  DebugConnection(this.inner) {
    _out = StreamController<String>(
      onListen: () {
        _subscription = inner.messages.listen(
          (frame) {
            _record(frame);
            _out.add(frame);
          },
          onError: _out.addError,
          onDone: _out.close,
        );
      },
      onCancel: () => _subscription?.cancel(),
    );
  }

  final SignallingConnection inner;
  late final StreamController<String> _out;
  StreamSubscription<String>? _subscription;
  String? _lastConfiguration;
  final List<String> sent = [];
  final List<String> received = [];
  final List<String> offerUfrags = [];

  void _record(String frame) {
    try {
      final json = jsonDecode(frame);
      if (json is! Map) return;
      received.add('${json['type']}');
      if (json['type'] == 'rtcConfiguration') _lastConfiguration = frame;
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
    final json = jsonDecode(frame) as Map;
    sent.add(json['type']! as String);
    if (json['type'] == 'offer') {
      final match = RegExp(r'a=ice-ufrag:(\S+)').firstMatch('${json['sdp']}');
      offerUfrags.add(match?.group(1) ?? '');
    }
    inner.send(frame);
  }

  @override
  Future<void> close() => inner.close();
}

final class DebugPeers implements PeerTransportFactory {
  DebugPeers(this._inner);

  final PeerTransportFactory _inner;
  PeerTransport? last;

  @override
  Future<PeerTransport> create(
    Map<String, Object?> rtcConfiguration, {
    required StreamConfig config,
    required bool muted,
  }) async {
    final peer = await _inner.create(
      rtcConfiguration,
      config: config,
      muted: muted,
    );
    last = peer;
    return peer;
  }
}
