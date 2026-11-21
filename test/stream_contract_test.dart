// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

// Stream client contract v1: a fresh key per connect, error reasons, labels.
import 'dart:async';

import 'package:flutter/foundation.dart' show DebugPrintCallback, debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';
import 'package:mobilerun_flutter/src/core/stream_transports.dart';

import 'support/harness.dart';

StreamCredentials _provider(StreamTokenProvider provider) =>
    StreamCredentials(url: 'wss://stream.test/s', tokenProvider: provider);

void main() {
  late List<String> diagnostics;
  late DebugPrintCallback previousDebugPrint;
  setUp(() {
    diagnostics = [];
    previousDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) diagnostics.add(message);
    };
  });
  tearDown(() => debugPrint = previousDebugPrint);

  group('fresh key per connect', () {
    test('every reconnect after an open session mints a new key', () async {
      var calls = 0;
      final h = Harness(
        credentials: (_) => StreamCredentials(
          url: 'wss://stream.test/s',
          token: 'static',
          tokenProvider: () async => 'key-${++calls}',
        ),
      );
      await h.connect();
      h.ws.serverClose();
      await pump();
      await h.advance(1000);
      h.ws.serverClose();
      await pump();
      await h.advance(2000);
      final tokens = h.connector.uris
          .map((uri) => uri.queryParameters['token'])
          .toList();
      expect(tokens, ['key-1', 'key-2', 'key-3']);
      expect(calls, 3);
      await h.session.close();
    });

    test('the provider wins over a static token', () async {
      final h = Harness(
        credentials: (_) => StreamCredentials(
          url: 'wss://stream.test/s',
          token: 'static',
          tokenProvider: () async => 'minted',
        ),
      );
      h.session.start();
      await pump();
      expect(h.connector.uris.single.queryParameters['token'], 'minted');
      expect(diagnostics, isEmpty);
      await h.session.close();
    });

    test('a static token still connects and warns once per session', () async {
      final h = Harness(
        credentials: (_) =>
            const StreamCredentials(url: 'wss://stream.test/s', token: 'old'),
      );
      await h.connect();
      h.ws.serverClose();
      await pump();
      await h.advance(1000);
      expect(h.connector.uris, hasLength(2));
      expect(h.connector.uris.map((uri) => uri.queryParameters['token']), [
        'old',
        'old',
      ]);
      expect(
        diagnostics.where((line) => line.contains('token is deprecated')),
        hasLength(1),
      );
      await h.session.close();
    });
  });

  group('onError reasons', () {
    test('a throwing provider is credentials_unavailable', () async {
      final h = Harness(
        credentials: (_) => _provider(() => throw StateError('private-canary')),
      );
      h.session.start();
      await pump();
      final error = h.errors.single;
      expect(error.reason, StreamErrorReason.credentialsUnavailable);
      expect(error.reason.code, 'credentials_unavailable');
      expect(error.attempt, 1);
      expect(error.isFinal, isFalse);
      expect(error.message, isNot(contains('private-canary')));
      expect(h.connector.uris, isEmpty);
      await h.session.close();
    });

    test('a provider that never answers times out after 10 s', () async {
      final h = Harness(
        credentials: (_) => _provider(() => Completer<String>().future),
      );
      h.session.start();
      await pump();
      await h.advance(9999);
      expect(h.errors, isEmpty);
      await h.advance(1);
      expect(h.errors.single.reason, StreamErrorReason.credentialsUnavailable);
      await h.session.close();
    });

    test('a socket that fails to open is connection_refused', () async {
      final h = Harness(credentials: (_) => _provider(() async => 'key'));
      h.connector.failWith = StateError('refused');
      h.session.start();
      await pump();
      final error = h.errors.single;
      expect(error.reason, StreamErrorReason.connectionRefused);
      expect(error.attempt, 1);
      expect(error.isFinal, isFalse);
      expect(error.toString(), isNot(contains('key')));
      await h.session.close();
    });

    test('HTTP 401 on the upgrade is token_rejected', () async {
      final h = Harness(credentials: (_) => _provider(() async => 'key'));
      h.connector.failWith = const SignallingRejectedException(401);
      h.session.start();
      await pump();
      expect(h.errors.single.reason, StreamErrorReason.tokenRejected);
      await h.session.close();
    });

    test('HTTP 500 on the upgrade is connection_refused', () async {
      final h = Harness(credentials: (_) => _provider(() async => 'key'));
      h.connector.failWith = const SignallingRejectedException(500);
      h.session.start();
      await pump();
      expect(h.errors.single.reason, StreamErrorReason.connectionRefused);
      await h.session.close();
    });

    test('a dropped open session is disconnected', () async {
      final h = Harness();
      await h.connect();
      expect(h.errors, isEmpty);
      h.ws.serverClose();
      await pump();
      expect(h.errors.single.reason, StreamErrorReason.disconnected);
      expect(h.errors.single.attempt, 1);
      await h.session.close();
    });

    test('a failed peer connection is disconnected', () async {
      final h = Harness();
      await h.connect();
      h.peer.emitState(PeerState.failed);
      await pump();
      expect(h.errors.single.reason, StreamErrorReason.disconnected);
      await h.session.close();
    });

    test('a missing rtc configuration is unknown', () async {
      final h = Harness();
      h.session.start();
      await pump();
      // The socket opened but the server never sends its configuration.
      await h.advance(15000);
      expect(h.errors.single.reason, StreamErrorReason.unknown);
      await h.session.close();
    });

    test('final is set when retries stop, and only then', () async {
      final h = Harness(credentials: (_) => _provider(() async => 'key'));
      h.connector.failWith = StateError('refused');
      h.session.start();
      await pump();
      for (
        var i = 0;
        i < 40 && h.session.status.value is! StreamUnavailable;
        i++
      ) {
        await h.advance(30000);
      }
      expect(h.session.status.value, const StreamUnavailable());
      final errors = h.errors;
      expect(errors.length, ReconnectPolicy.maxAttempts + 1);
      expect(errors.map((e) => e.attempt), [1, 2, 3, 4, 5, 6, 7]);
      expect(errors.take(6).every((e) => !e.isFinal), isTrue);
      expect(errors.last.isFinal, isTrue);
      final count = errors.length;
      await h.advance(60000);
      expect(h.errors.length, count);
      await h.session.close();
    });

    test('a throwing onError does not break reconnecting', () async {
      final h = Harness(
        credentials: (_) => _provider(() async => 'key'),
        onError: (_) => throw StateError('app bug'),
      );
      h.connector.failWith = StateError('refused');
      h.session.start();
      await pump();
      h.connector.failWith = null;
      await h.advance(1000);
      expect(h.connector.connections, hasLength(1));
      expect(
        diagnostics,
        contains('[mobilerun.stream] onError threw: StateError'),
      );
      await h.session.close();
    });
  });
}
