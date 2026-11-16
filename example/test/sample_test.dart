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
