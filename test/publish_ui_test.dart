// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';
import 'package:mobilerun_flutter/src/webrtc/webrtc_initializer.dart';

import 'support/fake_transports.dart';
import 'support/harness.dart';
import 'publish_test.dart' show publishCapabilities, respond;
import 'device_stream_test.dart' show closeSession;

const labels = StreamLabels(
  microphone: 'Mic on',
  camera: 'Camera on',
  stopMicrophone: 'Mic off',
  stopCamera: 'Camera off',
  publishStarting: 'Waiting',
  publishPermissionDenied: 'Allow local inputs',
  publishNotAllowed: 'Inputs refused',
);
const boundaryKey = ValueKey('stream-screenshot');

Future<void> mount(WidgetTester tester, Harness h, {bool show = true}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RepaintBoundary(
          key: boundaryKey,
          child: DeviceStream(
            session: h.session,
            labels: labels,
            showPublishControls: show,
            observeLifecycle: false,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> flush(WidgetTester tester) async {
  for (var turn = 0; turn < 3; turn++) {
    await tester.pump();
    await tester.runAsync(pump);
  }
  await tester.pump();
}

Future<void> screenshot(WidgetTester tester, String name) async {
  final directory = Platform.environment['PUBLISH_SCREENSHOTS'];
  if (directory == null) return;
  await tester.pump(const Duration(milliseconds: 250));
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(boundaryKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = Platform.environment['PUBLISH_ICON_FONT'];
    if (font != null) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(
          File(font).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      await loader.load();
    }
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('FlutterWebRTC.Method'),
      (_) async => null,
    );
    await ensureWebRtcInitialized();
  });
  setUp(() {
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
  });

  for (final row in <(DevicePublishCapabilities?, bool, bool)>[
    (null, true, false),
    (publishCapabilities, false, false),
    (
      const DevicePublishCapabilities(
        microphoneInjection: false,
        cameraInjection: true,
        mediaInjectionTransport: 'direct',
      ),
      true,
      false,
    ),
    (
      const DevicePublishCapabilities(
        microphoneInjection: true,
        cameraInjection: true,
        mediaInjectionTransport: 'other',
      ),
      true,
      false,
    ),
    (publishCapabilities, true, true),
  ]) {
    testWidgets('pill visibility capabilities=${row.$1} prop=${row.$2}', (
      tester,
    ) async {
      final h = Harness(
        config: StreamConfig(publishCapabilities: row.$1),
        publishCapture: FakePublishCapture(),
      );
      await mount(tester, h, show: row.$2);
      expect(find.byTooltip('Mic on'), row.$3 ? findsOneWidget : findsNothing);
      await tester.pumpWidget(const SizedBox());
      await closeSession(tester, h.session);
    });
  }

  for (final width in [375.0, 1280.0]) {
    testWidgets('mic/camera click-through and overlay geometry at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final capture = FakePublishCapture();
      final h = Harness(
        config: const StreamConfig(publishCapabilities: publishCapabilities),
        publishCapture: capture,
      );
      await tester.runAsync(h.connect);
      await mount(tester, h, show: false);
      final before = tester.getRect(find.byType(DeviceStreamView));
      await screenshot(tester, '${width.toInt()}-before');
      await mount(tester, h);
      expect(tester.getRect(find.byType(DeviceStreamView)), before);
      final pill = tester.getRect(find.byTooltip('Mic on'));
      expect(pill.center.dx, lessThan(width / 2));
      expect(pill.bottom, lessThan(before.bottom));
      await screenshot(tester, '${width.toInt()}-idle');
      await tester.tap(find.byTooltip('Camera on'));
      await flush(tester);
      await tester.pump();
      expect(find.text('Waiting'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Mic on',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.runAsync(() async {
        respond(h, 'active');
        await pump();
      });
      await flush(tester);
      expect(find.byTooltip('Mic off'), findsOneWidget);
      expect(find.byTooltip('Camera off'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Mic off',
              ),
            )
            .color,
        const StreamTokens().destructive,
      );
      await screenshot(tester, '${width.toInt()}-active');
      // Removing camera explicitly stops then starts microphone-only with a new ID.
      await tester.tap(find.byTooltip('Camera off'));
      await tester.pump();
      await flush(tester);
      await tester.pump();
      expect(h.session.publishState.value.phase, PublishPhase.starting);
      await tester.runAsync(() async {
        respond(h, 'active');
        await pump();
      });
      await flush(tester);
      expect(h.ws.ofType('publishStart').last.json['kinds'], ['audio']);
      expect(find.byTooltip('Camera on'), findsOneWidget);
      await tester.tap(find.byTooltip('Mic off'));
      await flush(tester);
      await tester.pump();
      expect(
        capture.media.every(
          (media) => media.tracks.every((track) => track.stopped),
        ),
        isTrue,
      );
      expect(h.session.status.value, isA<StreamConnected>());
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Mic on',
              ),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byTooltip('Mic on'));
      await flush(tester);
      expect(h.session.publishState.value.phase, PublishPhase.starting);
      await tester.runAsync(() async {
        respond(h, 'rejected', reason: 'forbidden');
        await pump();
      });
      await flush(tester);
      expect(h.session.publishState.value.phase, PublishPhase.error);
      expect(h.session.publishState.value.reason, 'publish_not_allowed');
      expect(find.text('Inputs refused'), findsOneWidget);
      await screenshot(tester, '${width.toInt()}-forbidden');
      await tester.pumpWidget(const SizedBox());
      await closeSession(tester, h.session);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'permission label and no camera control without a local encoder',
    (tester) async {
      final capture = FakePublishCapture()
        ..error = const PublishException(
          PublishFailure(
            reason: StreamErrorReason.permissionDenied,
            message: 'Not displayed',
            detail: 'capture_permission',
          ),
        );
      final h = Harness(
        config: const StreamConfig(publishCapabilities: publishCapabilities),
        publishCapture: capture,
      );
      h.peers.publishKinds = {PublishKind.audio};
      await tester.runAsync(h.connect);
      await mount(tester, h);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Mic on',
              ),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byTooltip('Mic on'));
      await flush(tester);
      expect(h.session.publishState.value.phase, PublishPhase.error);
      await tester.pump();
      expect(find.text('Allow local inputs'), findsOneWidget);
      expect(find.byTooltip('Camera on'), findsNothing);
      expect(find.text('Not displayed'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await closeSession(tester, h.session);
    },
  );

  test('new labels copy and equality include every publish string', () {
    expect(labels.copyWith(), labels);
    expect(labels.copyWith().hashCode, labels.hashCode);
    expect(labels.copyWith(camera: 'Kamera'), isNot(labels));
    expect(labels.copyWith(camera: 'Kamera').camera, 'Kamera');
    expect(
      labels
          .copyWith(publishPermissionDenied: 'Denied')
          .publishPermissionDenied,
      'Denied',
    );
  });
}
