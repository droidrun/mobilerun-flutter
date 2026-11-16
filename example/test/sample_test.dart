// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';
import 'package:mobilerun_flutter_example/main.dart';
import 'package:mobilerun_flutter_example/sample_credentials.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('sample-test-'));
  tearDown(() => dir.deleteSync(recursive: true));

  test(
    'launch file is consumed once and credentials redact the token',
    () async {
      final file = File('${dir.path}/sample.json');
      await file.writeAsString(
        '{"streamUrl":"wss://example.com", "streamToken":"secret-canary"}',
      );
      final credentials = await consumeCredentials(file);
      expect(credentials?.url, 'wss://example.com');
      expect(credentials?.token, 'secret-canary');
      expect(credentials.toString(), isNot(contains('secret-canary')));
      expect(await file.exists(), isFalse);
      expect(await consumeCredentials(file), isNull);
    },
  );

  for (final input in [
    '{}',
    '{"streamUrl":" ","streamToken":"x"}',
    '{"streamUrl":"wss://example.com","streamToken":" "}',
    '{"streamUrl":12,"streamToken":"secret-canary"}',
    'secret-canary',
  ]) {
    test(
      'invalid launch file is rejected and deleted: ${input.length} chars',
      () async {
        final file = File('${dir.path}/sample.json');
        await file.writeAsString(input);
        await expectLater(
          consumeCredentials(file),
          throwsA(
            isA<FormatException>().having(
              (error) => error.toString(),
              'safe error',
              isNot(contains('secret-canary')),
            ),
          ),
        );
        expect(await file.exists(), isFalse);
      },
    );
  }

  testWidgets('approval counts down, approves/denies and refetches', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DemoApproval())),
    );
    await tester.tap(find.text('Demo approval'));
    await tester.pump();
    expect(find.textContaining('30s'), findsOneWidget);
    await tester.tap(find.text('Approve'));
    await tester.pump();
    expect(find.text('Decision: approve; refetches: 1'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
    await tester.tap(find.text('Demo approval'));
    await tester.pump();
    await tester.tap(find.text('Deny'));
    await tester.pump();
    expect(find.text('Decision: deny; refetches: 1'), findsOneWidget);
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
