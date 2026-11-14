// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStream;
import 'package:mobilerun_flutter/mobilerun_flutter.dart';

import 'device_stream_session_test.dart' show Harness;

class _Stream implements MediaStream {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
  @override
  String get id => 'video-test';
  @override
  String get ownerTag => 'remote';
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('FlutterWebRTC.Method'),
      (call) async =>
          call.method == 'createVideoRenderer' ? {'textureId': 1} : null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('FlutterWebRTC/Texture1'),
      (_) async => null,
    );
  });

  Future<Harness> mount(
    WidgetTester tester,
    DeviceStreamController controller,
  ) async {
    final h = Harness();
    await tester.runAsync(h.connect);
    await tester.runAsync(() async {
      h.peer.emitVideo(_Stream());
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 400,
            child: DeviceStream(
              session: h.session,
              hasControl: true,
              controller: controller,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      'FlutterWebRTC/Texture1',
      const StandardMethodCodec().encodeSuccessEnvelope({
        'event': 'didTextureChangeVideoSize',
        'width': 200,
        'height': 400,
      }),
      (_) {},
    );
    await tester.pump();
    return h;
  }

  testWidgets(
    'view routes touch, coalesces MOVE, hover only on hover channel',
    (tester) async {
      final controller = DeviceStreamController();
      final h = await mount(tester, controller);
      expect(
        controller.renderedVideoRect,
        const Rect.fromLTWH(100, 0, 200, 400),
      );
      final topLeft = tester.getTopLeft(find.byType(DeviceStream));
      await tester.tapAt(topLeft + const Offset(50, 50));
      expect(h.peer.controlChannel.sent, isEmpty);
      final finger = await tester.startGesture(
        topLeft + const Offset(200, 100),
        pointer: 10,
      );
      await finger.moveTo(topLeft + const Offset(210, 110));
      await finger.moveTo(topLeft + const Offset(220, 120));
      await tester.pump();
      await finger.moveTo(topLeft + const Offset(10, 10));
      await finger.up();
      expect(h.peer.controlChannel.sent.map((b) => b[1]), [0, 2, 1]);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: topLeft + const Offset(200, 100));
      await mouse.moveTo(topLeft + const Offset(210, 110));
      expect(h.peer.hoverChannel.sent.last[0], 21);
      expect(h.peer.controlChannel.sent.every((b) => b[0] != 21), isTrue);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(h.session.close);
      expect(controller.renderedVideoRect, isNull);
    },
  );

  testWidgets(
    'hardware, clipboard, IME, system keys and display-only routing',
    (tester) async {
      final controller = DeviceStreamController();
      final h = await mount(tester, controller);
      controller.showKeyboard();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'a');
      expect(h.peer.controlChannel.sent, [encodeText('a')]);
      h.peer.controlChannel.sent.clear();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => call.method == 'Clipboard.getData'
            ? {'text': 'clipboard text'}
            : null,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV, character: 'v');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(h.peer.controlChannel.sent.any((b) => b[0] == 9), isTrue);
      h.peer.controlChannel.sent.clear();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '\u200b日本',
          composing: TextRange(start: 1, end: 3),
        ),
      );
      await tester.pump();
      expect(h.peer.controlChannel.sent, isEmpty);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(text: '\u200b日本'),
      );
      await tester.pump();
      expect(h.peer.controlChannel.sent, [encodeText('日本')]);
      controller.sendSystemKey(DeviceSystemKey.back);
      expect(
        h.peer.controlChannel.sent.last,
        encodeKeycode(action: 1, keycode: 4),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 400,
              height: 400,
              child: DeviceStream(
                session: h.session,
                hasControl: false,
                controller: controller,
              ),
            ),
          ),
        ),
      );
      h.peer.controlChannel.sent.clear();
      controller.showKeyboard();
      controller.sendSystemKey(DeviceSystemKey.home);
      await tester.tap(find.byType(DeviceStream));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(h.peer.controlChannel.sent, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(h.session.close);
    },
  );
}
