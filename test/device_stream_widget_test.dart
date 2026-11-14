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
  testWidgets(
    'recording session receives exact input bytes from the mounted view',
    (tester) async {
      final controller = DeviceStreamController();
      final h = await mount(tester, controller);
      final origin = tester.getTopLeft(find.byType(DeviceStream));
      Uint8List touch(int action, int slot, double x, double y) => encodeTouch(
        action: action,
        pointerId: slot,
        videoWidth: 200,
        videoHeight: 400,
        x: x,
        y: y,
        pressure: 1,
        actionButton: 1,
        buttons: 1,
      );
      List<Uint8List> press(int keycode) => [
        encodeKeycode(action: 0, keycode: keycode),
        encodeKeycode(action: 1, keycode: keycode),
      ];
      final first = await tester.startGesture(
        origin + const Offset(150, 100),
        pointer: 501,
      );
      final second = await tester.startGesture(
        origin + const Offset(250, 200),
        pointer: 912,
      );
      await first.moveTo(origin + const Offset(160, 110));
      await first.moveTo(origin + const Offset(170, 120));
      await tester.pump();
      await second.cancel();
      await first.up();
      expect(h.peer.controlChannel.sent, [
        touch(0, 0, 50, 100),
        touch(0, 1, 150, 200),
        touch(2, 0, 70, 120),
        touch(3, 1, 150, 200),
        touch(1, 0, 70, 120),
      ]);
      h.peer.controlChannel.sent.clear();
      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        pointer: 1010,
      );
      await mouse.addPointer(location: origin + const Offset(180, 130));
      await mouse.down(origin + const Offset(180, 130));
      await mouse.moveTo(origin + const Offset(190, 140));
      await tester.pump();
      await mouse.up();
      expect(h.peer.controlChannel.sent, [
        touch(0, -1, 80, 130),
        touch(2, -1, 90, 140),
        touch(1, -1, 90, 140),
      ]);
      h.peer.controlChannel.sent.clear();
      h.peer.hoverChannel.sent.clear();
      await tester.sendEventToBinding(
        PointerHoverEvent(
          position: origin + const Offset(200, 150),
          buttons: 2,
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: origin + const Offset(200, 150),
          scrollDelta: const Offset(100, -200),
          kind: PointerDeviceKind.mouse,
        ),
      );
      expect(h.peer.hoverChannel.sent, [
        encodeHover(
          videoWidth: 200,
          videoHeight: 400,
          x: 100,
          y: 150,
          buttons: 2,
        ),
      ]);
      expect(h.peer.controlChannel.sent, [
        encodeScroll(
          videoWidth: 200,
          videoHeight: 400,
          x: 100,
          y: 150,
          hscrollTicks: -1,
          vscrollTicks: 2,
          buttons: 0,
        ),
      ]);
      h.peer.controlChannel.sent.clear();
      controller.showKeyboard();
      await tester.pump();
      expect(
        tester.testTextInput.setClientArgs!['inputType'],
        containsPair('name', 'TextInputType.visiblePassword'),
      );
      expect(tester.testTextInput.setClientArgs!['autocorrect'], isFalse);
      expect(tester.testTextInput.setClientArgs!['enableSuggestions'], isFalse);
      expect(
        await tester.sendKeyEvent(
          LogicalKeyboardKey.audioVolumeUp,
          physicalKey: PhysicalKeyboardKey.audioVolumeUp,
          character: 'x',
        ),
        isFalse,
      );
      expect(h.peer.controlChannel.sent, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'a');
      await tester.sendKeyEvent(
        LogicalKeyboardKey.numpadEnter,
        physicalKey: PhysicalKeyboardKey.numpadEnter,
        character: '\n',
      );
      expect(h.peer.controlChannel.sent, [encodeText('a'), ...press(160)]);
      h.peer.controlChannel.sent.clear();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(text: '\u200bs'),
      );
      await tester.pump();
      expect(h.peer.controlChannel.sent, [encodeText('s')]);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(text: '\u200bt'),
      );
      await tester.pump();
      expect(h.peer.controlChannel.sent, [encodeText('s'), encodeText('t')]);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '\u200b日本',
          composing: TextRange(start: 1, end: 3),
        ),
      );
      await tester.pump();
      expect(h.peer.controlChannel.sent.length, 2);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(text: '\u200b日本'),
      );
      await tester.pump();
      tester.testTextInput.updateEditingValue(TextEditingValue.empty);
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      for (final key in DeviceSystemKey.values) {
        controller.sendSystemKey(key);
      }
      expect(h.peer.controlChannel.sent, [
        encodeText('s'),
        encodeText('t'),
        encodeText('日本'),
        ...press(67),
        ...press(66),
        ...press(4),
        ...press(3),
        ...press(187),
      ]);
      h.peer.controlChannel.sent.clear();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '\u200bhide',
          composing: TextRange(start: 1, end: 5),
        ),
      );
      await tester.pump();
      controller.hideKeyboard();
      await tester.pump();
      expect(h.peer.controlChannel.sent, [encodeText('hide')]);
      expect(tester.testTextInput.isVisible, isFalse);
      await mouse.removePointer();
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
      h.peer.hoverChannel.sent.clear();
      final ignored = await tester.startGesture(
        origin + const Offset(200, 150),
        pointer: 2020,
      );
      await ignored.moveTo(origin + const Offset(220, 170));
      await ignored.cancel();
      await tester.sendEventToBinding(
        PointerHoverEvent(
          position: origin + const Offset(200, 150),
          buttons: 2,
        ),
      );
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: origin + const Offset(200, 150),
          scrollDelta: const Offset(0, 100),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(text: 'ignored'),
      );
      for (final key in DeviceSystemKey.values) {
        controller.sendSystemKey(key);
      }
      controller.showKeyboard();
      controller.hideKeyboard();
      await tester.pump();
      expect(h.peer.controlChannel.sent, isEmpty);
      expect(h.peer.hoverChannel.sent, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(h.session.close);
    },
  );

  testWidgets(
    'hide and disposal never clear or hide the host editor keyboard',
    (tester) async {
      final controller = DeviceStreamController();
      final h = Harness();
      final hostFocus = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Column(
              children: [
                Expanded(
                  child: DeviceStream(
                    session: h.session,
                    hasControl: true,
                    controller: controller,
                  ),
                ),
                TextField(focusNode: hostFocus),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      controller.showKeyboard();
      await tester.pump();
      hostFocus.requestFocus();
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
      final client = tester.testTextInput.setClientArgs;
      tester.testTextInput.log.clear();
      controller.hideKeyboard();
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
      expect(tester.testTextInput.setClientArgs, client);
      expect(
        tester.testTextInput.log.where(
          (c) =>
              c.method == 'TextInput.hide' ||
              c.method == 'TextInput.clearClient',
        ),
        isEmpty,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Column(
              children: [
                const Expanded(child: SizedBox()),
                TextField(focusNode: hostFocus),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
      expect(
        tester.testTextInput.log.where(
          (c) =>
              c.method == 'TextInput.hide' ||
              c.method == 'TextInput.clearClient',
        ),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      hostFocus.dispose();
      await tester.runAsync(h.session.close);
    },
  );
}
