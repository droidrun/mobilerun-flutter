// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';
import 'package:mobilerun_flutter_example/main.dart';
import 'package:mobilerun_flutter_example/sample_backend.dart';
import 'package:mobilerun_flutter/src/webrtc/webrtc_initializer.dart';
import 'package:mobilerun_flutter_example/sample_credentials.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('FlutterWebRTC.Method'),
      (_) async => null,
    );
    await ensureWebRtcInitialized();
  });

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('sample-test-'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('launch file trims credentials and is consumed once', () async {
    final file = File('${dir.path}/sample.json');
    await file.writeAsString(
      '{"streamUrl":"  wss://example.com  ", "streamToken":"  secret-canary  "}',
    );
    final credentials = await consumeCredentials(file);
    expect(credentials?.url, 'wss://example.com');
    expect(credentials?.token, 'secret-canary');
    expect(await file.exists(), isFalse);
    expect(await consumeCredentials(file), isNull);
  });

  for (final entry in {
    'missing fields': '{}',
    'blank URL': '{"streamUrl":" ","streamToken":"x"}',
    'blank token': '{"streamUrl":"wss://example.com","streamToken":" "}',
    'wrong field type': '{"streamUrl":12,"streamToken":"secret-canary"}',
    'malformed JSON': 'secret-canary',
    'json array': '[]',
    'missing helper device': '{"helperBaseUrl":"http://localhost:3001"}',
    'invalid helper scheme':
        '{"helperBaseUrl":"file:///tmp/helper","deviceId":"a"}',
    'helper credentials':
        '{"helperBaseUrl":"http://key@localhost:3001","deviceId":"a"}',
  }.entries) {
    test('rejects and deletes ${entry.key}', () async {
      final file = File('${dir.path}/sample.json');
      await file.writeAsString(entry.value);
      await expectLater(
        consumeCredentials(file),
        throwsA(isA<FormatException>()),
      );
      expect(await file.exists(), isFalse);
    });
  }

  test(
    'helper launch is credential-free, consumed once and binds its device',
    () async {
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requests = <String>[];
      server.listen((request) async {
        requests.add('${request.method} ${request.uri.path}');
        request.response.headers.contentType = ContentType.json;
        request.response.statusCode = request.method == 'POST' ? 201 : 200;
        request.response.write(
          jsonEncode(
            request.method == 'POST'
                ? {'key': 'mint-canary', 'keyId': 'id', 'expiresAt': 'later'}
                : {
                    'id': 'device-a',
                    'state': 'running',
                    'streamUrl': 'wss://stream.test/a',
                  },
          ),
        );
        await request.response.close();
      });
      final file = File('${dir.path}/sample.json');
      await file.writeAsString(
        jsonEncode({
          'helperBaseUrl': 'http://127.0.0.1:${server.port}',
          'deviceId': 'device-a',
        }),
      );
      final launch = (await consumeLaunch(file))!;
      expect(await file.exists(), isFalse);
      expect(await consumeLaunch(file), isNull);
      expect(launch.credentials, isNull);
      final target = (await launch.backend!.credentials())!;
      expect(target.url, 'wss://stream.test/a');
      expect(target.token, isNull);
      expect(requests, ['GET /api/v1/devices/device-a']);
      expect(await target.tokenProvider!(), 'mint-canary');
      expect(await target.tokenProvider!(), 'mint-canary');
      expect(target.token, isNull);
      expect(target.toString(), isNot(contains('mint-canary')));
      expect(requests, [
        'GET /api/v1/devices/device-a',
        'POST /api/v1/devices/device-a/stream-key',
        'POST /api/v1/devices/device-a/stream-key',
      ]);
    },
  );

  test('helper errors never expose upstream response text', () async {
    final previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previousOverrides);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.statusCode = 403;
      request.response.write('private-canary');
      await request.response.close();
    });
    final file = File('${dir.path}/sample.json');
    await file.writeAsString(
      jsonEncode({
        'helperBaseUrl': 'http://127.0.0.1:${server.port}',
        'deviceId': 'device-a',
      }),
    );
    final launch = (await consumeLaunch(file))!;
    await expectLater(
      launch.backend!.credentials(),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Backend request failed',
        ),
      ),
    );
  });

  testWidgets(
    'helper reconnect never puts minted keys into the credential form',
    (tester) async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('FlutterWebRTC.Method'),
        (call) async =>
            call.method == 'createVideoRenderer' ? {'textureId': 1} : null,
      );
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('FlutterWebRTC.Event'),
        (_) async => null,
      );
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('FlutterWebRTC/Texture1'),
        (_) async => null,
      );
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);
      final server = (await tester.runAsync(
        () => HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      ))!;
      addTearDown(() => server.close(force: true));
      final upgrades = StreamController<WebSocket>();
      addTearDown(upgrades.close);
      final sockets = StreamIterator(upgrades.stream);
      addTearDown(sockets.cancel);
      var mints = 0;
      server.listen((request) async {
        if (request.uri.path == '/stream') {
          final socket = await WebSocketTransformer.upgrade(request);
          socket.listen((_) {});
          upgrades.add(socket);
          return;
        }
        final mint = request.method == 'POST';
        if (mint) mints++;
        request.response.statusCode = mint ? 201 : 200;
        request.response.write(
          jsonEncode(
            mint
                ? {'key': 'mint-canary-$mints'}
                : {'streamUrl': 'ws://127.0.0.1:${server.port}/stream'},
          ),
        );
        await request.response.close();
      });
      final backend = SampleBackend(
        baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
        deviceId: 'a',
      );
      await tester.pumpWidget(ExampleApp(backend: backend));
      var opened = false;
      final opening = sockets.moveNext().then((value) => opened = value);
      for (var i = 0; i < 100; i++) {
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      }
      expect(opened, isTrue);
      await opening;
      await tester.pump();
      await tester.tap(find.text('Credentials'));
      await tester.pump();
      expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .map((field) => field.controller!.text),
        ['', ''],
      );
      expect(find.textContaining('mint-canary'), findsNothing);
      await tester.tap(find.text('Reconnect'));
      await tester.pump();
      var reopened = false;
      final reopening = sockets.moveNext().then((value) => reopened = value);
      for (var i = 0; i < 100; i++) {
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      }
      expect(reopened, isTrue);
      await reopening;
      expect(mints, 2);
      await tester.pumpWidget(const SizedBox());
      unawaited(sockets.current.close());
      for (var i = 0; i < 20; i++) {
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      }
    },
  );

  testWidgets('token entry is obscured', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    final tokenField = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Stream token'),
    );
    expect(tokenField.obscureText, isTrue);
  });

  testWidgets('demo displays a seconds countdown and payment details', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DemoApproval())),
    );
    await tester.tap(find.text('Demo approval'));
    await tester.pump();
    expect(find.textContaining(RegExp(r'^\d+s left$')), findsOneWidget);
    expect(find.text('Visa 4242'), findsOneWidget);
    expect(find.text('com.shop'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('approve dismisses the demo with exactly one refetch', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DemoApproval())),
    );
    await tester.tap(find.text('Demo approval'));
    await tester.pump();
    // No polling fetches during the pending approval.
    await tester.pump(const Duration(seconds: 6));
    await tester.tap(find.text('Approve'));
    await tester.pump();
    expect(find.text('Decision: approve; refetches: 1'), findsOneWidget);
    expect(find.text('Approve payment'), findsNothing);
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('Decision: approve; refetches: 1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('deny dismisses the demo with exactly one refetch', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DemoApproval())),
    );
    await tester.tap(find.text('Demo approval'));
    await tester.pump();
    await tester.tap(find.text('Deny'));
    await tester.pump();
    expect(find.text('Decision: deny; refetches: 1'), findsOneWidget);
    expect(find.text('Approve payment'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('theme selector applies dark and brand tokens and labels', (
    tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    var context = tester.element(find.byType(DemoApproval));
    expect(StreamTheme.of(context).background, StreamTokens.dark.background);
    expect(Theme.of(context).brightness, Brightness.dark);
    await tester.tap(find.text('Brand'));
    await tester.pump();
    context = tester.element(find.byType(DemoApproval));
    expect(StreamTheme.of(context).primary, const Color(0xff005b50));
    expect(StreamTheme.of(context).radius, 12);
    await tester.tap(find.text('Demo approval'));
    await tester.pump();
    final card = tester.widget<TaskApprovalCard>(find.byType(TaskApprovalCard));
    expect(card.labels.approve, 'Allow');
    expect(card.labels.deny, 'Decline');
    await tester.pumpWidget(const SizedBox());
  });
}
