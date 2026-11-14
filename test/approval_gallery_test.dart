// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Exercise the shipped gallery without adding the example as an SDK dependency.
// ignore: avoid_relative_lib_imports
import '../example/lib/ui_gallery_main.dart';

void main() {
  testWidgets('gallery tolerates the initial zero-size native frame', (
    tester,
  ) async {
    tester.view.physicalSize = Size.zero;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: UiGallery()));
    await tester.pump();
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(375, 900);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Approve payment'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'gallery decisions remove the card and refetch without layout errors',
    (tester) async {
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: UiGallery()));
      await tester.pump();
      expect(find.text('Approve payment'), findsOneWidget);
      await tester.tap(find.text('Approve'));
      await tester.pump(const Duration(milliseconds: 701));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Approve payment'), findsNothing);
      expect(find.textContaining('Decision: approve;'), findsOneWidget);
      await tester.tap(find.text('light'));
      await tester.pump();
      await tester.tap(find.text('Deny'));
      await tester.pump(const Duration(milliseconds: 701));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Decision: deny;'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
