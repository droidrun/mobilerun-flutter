// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/stream_exception.dart';
import '../core/stream_transports.dart';

/// A [SignallingConnector] on `web_socket_channel`.
final class WebSocketSignallingConnector implements SignallingConnector {
  /// Creates the connector.
  const WebSocketSignallingConnector();

  @override
  Future<SignallingConnection> connect(Uri uri) async {
    final channel = WebSocketChannel.connect(uri);
    try {
      await channel.ready;
    } on Object catch (error) {
      unawaited(channel.sink.close().catchError((Object _) {}));
      final status = _httpStatus(error);
      if (status != null) throw SignallingRejectedException(status);
      // The error text can carry the URL, which carries the token.
      throw const StreamNotConnectedException();
    }
    return _WebSocketConnection(channel);
  }

  // `dart:io` reports a refused upgrade as "..., HTTP status code: 401" and
  // exposes the code only on its own exception type, which this file must not
  // import (the package also runs on the web). Only the status is read, never
  // the URL, which carries the token.
  static int? _httpStatus(Object error) {
    final match = RegExp(r'HTTP status code: (\d{3})').firstMatch('$error');
    return match == null ? null : int.parse(match.group(1)!);
  }
}

final class _WebSocketConnection implements SignallingConnection {
  _WebSocketConnection(this._channel);

  final WebSocketChannel _channel;

  @override
  Stream<String> get messages => _channel.stream.map(
    (data) => data is String
        ? data
        : utf8.decode(data as List<int>, allowMalformed: true),
  );

  @override
  void send(String frame) => _channel.sink.add(frame);

  @override
  Future<void> close({int code = 1000}) async {
    try {
      await _channel.sink.close(code);
    } on Object {
      // Closing an already closed socket is fine.
    }
  }
}
