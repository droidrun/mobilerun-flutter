// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilerun_flutter/src/webrtc/web_socket_signalling.dart';

void main() {
  test('native signalling sends a normal close frame before subscription cancellation', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final closed = Completer<int?>();
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((_) {}, onDone: () => closed.complete(socket.closeCode));
    });
    final connection = await const WebSocketSignallingConnector().connect(
      Uri.parse('ws://127.0.0.1:${server.port}/stream'),
    );
    final subscription = connection.messages.listen((_) {});
    await connection.close();
    expect(await closed.future.timeout(const Duration(seconds: 2)), 1000);
    await subscription.cancel();
  });
}
