// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';
import 'package:mobilerun_flutter/src/core/stream_transports.dart';

import 'support/harness.dart';
import 'support/fake_transports.dart';

import 'package:mobilerun_flutter/src/webrtc/web_socket_signalling.dart';

void main() {
  test(
    'real server close 1001 tears down media then reconnects with a fresh key',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final opened = StreamController<WebSocket>();
      addTearDown(opened.close);
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        opened.add(socket);
        socket.listen((_) {});
      });
      final sockets = StreamIterator(opened.stream);
      addTearDown(sockets.cancel);
      var calls = 0;
      final h = Harness(
        signalling: const WebSocketSignallingConnector(),
        credentials: (_) => StreamCredentials(
          url: 'ws://127.0.0.1:${server.port}/stream',
          tokenProvider: () async => 'key-${++calls}',
        ),
      );
      addTearDown(h.session.close);
      h.session.start();
      expect(await sockets.moveNext(), isTrue);
      final first = sockets.current;
      await pump();
      first.add(jsonEncode(example('server-rtc-configuration.json')));
      await pump();
      h.peer.emitState(PeerState.connected);
      h.peer.emitVideo(FakeMediaStream());
      await pump();
      final peer = h.peer;
      expect(h.session.videoStream.value, isNotNull);
      await first.close(1001);
      await pump();
      expect(peer.closed, isTrue);
      expect(h.session.videoStream.value, isNull);
      expect(h.session.status.value, const StreamReconnecting(1));
      await h.advance(1000);
      expect(await sockets.moveNext(), isTrue);
      expect(calls, 2);
      await h.session.close();
      await sockets.current.close();
    },
  );

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
