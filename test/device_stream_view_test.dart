// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart'
    show MediaStream, RTCVideoView;
import 'package:mobilerun_flutter/mobilerun_flutter.dart';
import 'package:mobilerun_flutter/src/protocol/control_messages.dart';

import 'support/harness.dart';

class _Video implements MediaStream {
  @override
  String get id => 'preview';
  @override
  String get ownerTag => 'remote';
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<void> mount(
  WidgetTester tester,
  Harness h, {
  bool hasControl = true,
  bool showNavigation = true,
  StreamLabels labels = const StreamLabels(),
  StreamOverlayBuilder placeholder = defaultStreamPlaceholder,
  StreamOverlayBuilder unavailable = defaultStreamUnavailable,
  StreamNavigationBuilder navigation = defaultStreamNavigation,
}) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(h.session.close);
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox(
          width: 400,
          height: 500,
          child: DeviceStreamView(
            session: h.session,
            hasControl: hasControl,
            showNavigation: showNavigation,
            labels: labels,
            placeholderBuilder: placeholder,
            unavailableBuilder: unavailable,
            navigationBuilder: navigation,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> exhaust(WidgetTester tester, Harness h) async {
  h.connector.failWith = StateError('offline');
  await tester.runAsync(() async {
    h.session.start();
    await pump();
  });
  for (var i = 0; i < 8 && h.session.status.value is! StreamUnavailable; i++) {
    await tester.runAsync(() => h.advance(30000));
  }
  await tester.pump();
  expect(h.session.status.value, isA<StreamUnavailable>());
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  var rendererCreates = 0;
  setUp(() {
    rendererCreates = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('FlutterWebRTC.Method'),
      (call) async {
        if (call.method == 'createVideoRenderer') {
          rendererCreates++;
          return {'textureId': 1};
        }
        return null;
      },
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('FlutterWebRTC/Texture1'),
      (_) async => null,
    );
  });

  testWidgets('connecting labels, corner pill and optional navigation', (
    tester,
  ) async {
    final h = Harness(credentials: (_) => null);
    await mount(tester, h, labels: const StreamLabels(connecting: 'Starting'));
    expect(find.text('Starting'), findsOneWidget);
    expect(find.byType(StreamStatusPill), findsOneWidget);
    final view = tester.widget<DeviceStream>(find.byType(DeviceStream));
    expect(view.hasControl, isTrue);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(
      tester.getBottomLeft(find.byType(StreamStatusPill)).dy,
      lessThan(tester.getBottomLeft(find.byType(DeviceStream)).dy),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 500,
          child: DeviceStreamView(session: h.session, showNavigation: false),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(StreamNavigationBar), findsNothing);
  });

  testWidgets(
    'connected keeps S3 video, navigation sends exact DOWN/UP pairs',
    (tester) async {
      final h = Harness();
      await tester.runAsync(h.connect);
      await tester.runAsync(() async {
        h.peer.emitVideo(_Video());
        await pump();
      });
      await mount(tester, h);
      expect(find.byType(RTCVideoView), findsOneWidget);
      expect(find.byType(StreamStatusPill), findsNothing);
      h.peer.controlChannel.sent.clear();
      for (final label in ['Back', 'Home', 'Recent']) {
        await tester.tap(find.byTooltip(label));
      }
      expect(h.peer.controlChannel.sent, [
        for (final code in [4, 3, 187]) ...[
          encodeKeycode(action: 0, keycode: code),
          encodeKeycode(action: 1, keycode: code),
        ],
      ]);
    },
  );

  testWidgets(
    'display-only keeps video and blocks view, navigation and controller input',
    (tester) async {
      final h = Harness();
      await tester.runAsync(h.connect);
      await tester.runAsync(() async {
        h.peer.emitVideo(_Video());
        await pump();
      });
      await mount(tester, h, hasControl: false);
      expect(find.byType(RTCVideoView), findsOneWidget);
      expect(
        tester.widget<DeviceStream>(find.byType(DeviceStream)).hasControl,
        isFalse,
      );
      expect(
        tester
            .widget<StreamNavigationBar>(find.byType(StreamNavigationBar))
            .state
            .canControl,
        isFalse,
      );
      h.peer.controlChannel.sent.clear();
      tester
          .widget<DeviceStream>(find.byType(DeviceStream))
          .controller!
          .sendSystemKey(DeviceSystemKey.back);
      await tester.tap(find.byTooltip('Home'));
      await tester.tap(find.byType(DeviceStream));
      expect(h.peer.controlChannel.sent, isEmpty);
    },
  );

  testWidgets('reconnect attempts, unavailable and retry share control rule', (
    tester,
  ) async {
    final h = Harness();
    h.connector.failWith = StateError('offline');
    await mount(tester, h);
    await tester.runAsync(() async {
      h.session.start();
      await pump();
    });
    await tester.pump();
    expect(find.text('reconnecting'), findsOneWidget);
    await tester.runAsync(() => h.advance(1000));
    await tester.pump();
    expect(find.text('reconnecting (2/6)'), findsOneWidget);
    await exhaust(tester, h);
    expect(find.text('device stream unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(
      tester.widget<DeviceStream>(find.byType(DeviceStream)).hasControl,
      isFalse,
    );
    expect(
      tester
          .widget<StreamNavigationBar>(find.byType(StreamNavigationBar))
          .state
          .canControl,
      isFalse,
    );
    final before = h.connector.uris.length;
    await tester.tap(find.text('Retry'));
    await tester.runAsync(pump);
    await tester.pump();
    expect(h.connector.uris.length, before + 1);
    expect(find.text('Retry'), findsNothing);
    expect(
      tester.widget<DeviceStream>(find.byType(DeviceStream)).hasControl,
      isTrue,
    );
  });

  testWidgets(
    'custom slots receive scoped container, state and working retry',
    (tester) async {
      final h = Harness();
      StreamOverlayState? overlay;
      StreamNavigationState? nav;
      await mount(
        tester,
        h,
        placeholder: (context, state) {
          overlay = state;
          return const Center(child: Text('custom placeholder'));
        },
        unavailable: (context, state) {
          overlay = state;
          return Center(
            child: TextButton(
              onPressed: state.retry,
              child: const Text('custom retry'),
            ),
          );
        },
        navigation: (context, state) {
          nav = state;
          return const SizedBox(height: 40, child: Text('custom navigation'));
        },
      );
      expect(find.text('custom placeholder'), findsOneWidget);
      expect(overlay!.constraints.biggest, const Size(400, 460));
      expect(nav!.canControl, isTrue);
      await exhaust(tester, h);
      expect(find.text('custom retry'), findsOneWidget);
      expect(nav!.canControl, isFalse);
      await tester.tap(find.text('custom retry'));
      await tester.runAsync(pump);
      await tester.pump();
      expect(find.text('custom retry'), findsNothing);
      expect(nav!.canControl, isTrue);
    },
  );

  testWidgets(
    'composite owns wake adapter and detaches on session replacement',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final old = Harness();
      old.connector.failWith = StateError('offline');
      final next = Harness();
      next.connector.failWith = StateError('offline');
      final online = StreamController<bool>.broadcast(sync: true);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(old.session.close);
        await tester.runAsync(next.session.close);
        await online.close();
      });
      await tester.runAsync(() async {
        old.session.start();
        next.session.start();
        await pump();
      });
      Widget view(Harness h) => MaterialApp(
        home: SizedBox(
          width: 400,
          height: 500,
          child: DeviceStreamView(
            session: h.session,
            connectivity: online.stream,
          ),
        ),
      );
      await tester.pumpWidget(view(old));
      await tester.pump();
      final oldBefore = old.connector.uris.length;
      online.add(true);
      await tester.runAsync(pump);
      await tester.pump();
      expect(old.connector.uris.length, oldBefore);
      online.add(false);
      online.add(true);
      await tester.runAsync(pump);
      await tester.pump();
      expect(old.connector.uris.length, oldBefore + 1);
      await tester.pumpWidget(view(next));
      await tester.pump();
      final nextBefore = next.connector.uris.length;
      online.add(true);
      await tester.runAsync(pump);
      expect(next.connector.uris.length, nextBefore);
      online.add(false);
      online.add(true);
      await tester.runAsync(pump);
      await tester.pump();
      expect(next.connector.uris.length, nextBefore + 1);
      expect(old.connector.uris.length, oldBefore + 1);
      await tester.pumpWidget(const SizedBox());
      online.add(false);
      online.add(true);
      await tester.runAsync(pump);
      expect(next.connector.uris.length, nextBefore + 1);
    },
  );

  testWidgets(
    'real composite renderer survives approval tabs and responsive resize',
    (tester) async {
      final h = Harness();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(h.session.close);
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final card = TaskApprovalCard(
        approval: const PendingApproval(approvalId: 'a'),
        onDecide: (_) {},
        device: DeviceStreamView(session: h.session),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: card)),
        ),
      );
      await tester.pump();
      expect(rendererCreates, 1);
      await tester.tap(find.text('Device'));
      await tester.pump();
      expect(find.byType(StreamNavigationBar), findsOneWidget);
      tester.view.physicalSize = const Size(1280, 900);
      await tester.pump();
      expect(rendererCreates, 1);
      expect(find.byType(DeviceStreamView), findsOneWidget);
      tester.view.physicalSize = const Size(375, 900);
      await tester.pump();
      await tester.tap(find.text('Details'));
      await tester.pump();
      expect(rendererCreates, 1);
      expect(
        find.byType(DeviceStreamView, skipOffstage: false),
        findsOneWidget,
      );
    },
  );
}
