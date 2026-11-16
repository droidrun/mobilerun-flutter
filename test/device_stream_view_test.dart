// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStream;
import 'package:mobilerun_flutter/mobilerun_flutter.dart';
import 'package:mobilerun_flutter/src/protocol/control_messages.dart';

import 'support/harness.dart';

class _Stream implements MediaStream {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
  @override
  String get id => 'video-test';
  @override
  String get ownerTag => 'remote';
}

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

bool hideOrClear(MethodCall call) =>
    call.method == 'TextInput.hide' || call.method == 'TextInput.clearClient';

Future<Harness> pumpView(
  WidgetTester tester, {
  Harness? harness,
  DeviceStreamController? controller,
  bool hasControl = true,
  Key? viewKey,
  Widget Function(Widget)? wrap,
}) async {
  final h = harness ?? Harness();
  if (h.peers.peers.isEmpty) {
    await tester.runAsync(h.connect);
    await tester.runAsync(() async {
      h.peer.emitVideo(_Stream());
      await Future<void>.delayed(Duration.zero);
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(h.session.close);
    });
  }
  final view = SizedBox(
    width: 400,
    height: 400,
    child: DeviceStreamView(
      key: viewKey,
      session: h.session,
      hasControl: hasControl,
      controller: controller,
    ),
  );
  await tester.pumpWidget(
    MaterialApp(home: wrap?.call(view) ?? Center(child: view)),
  );
  await tester.pump();
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
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

  testWidgets('two fingers have stable slots, coalesced MOVE and CANCEL', (
    tester,
  ) async {
    final h = await pumpView(tester);
    final origin = tester.getTopLeft(find.byType(DeviceStreamView));
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
  });

  testWidgets('outside DOWN ignored, outside UP uses the last in-video point', (
    tester,
  ) async {
    final h = await pumpView(tester);
    final origin = tester.getTopLeft(find.byType(DeviceStreamView));
    await tester.tapAt(origin + const Offset(50, 50));
    final finger = await tester.startGesture(origin + const Offset(200, 100));
    await finger.moveTo(origin + const Offset(10, 10));
    await finger.up();
    expect(h.peer.controlChannel.sent, [
      touch(0, 0, 100, 100),
      touch(1, 0, 100, 100),
    ]);
  });

  for (final mode in ['controlled video', 'letterbox', 'display only']) {
    testWidgets('ancestor ListView arena: $mode', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final h = await pumpView(
        tester,
        hasControl: mode != 'display only',
        wrap: (view) => ListView(
          controller: scroll,
          children: [
            Center(child: view),
            const SizedBox(height: 1200),
          ],
        ),
      );
      final origin = tester.getTopLeft(find.byType(DeviceStreamView));
      final x = mode == 'letterbox' ? 50.0 : 200.0;
      final finger = await tester.startGesture(origin + Offset(x, 300));
      await finger.moveTo(origin + Offset(x, 200));
      await tester.pump();
      await finger.moveTo(origin + Offset(x, 150));
      await tester.pump();
      await finger.up();
      await tester.pumpAndSettle();
      if (mode == 'controlled video') {
        expect(scroll.offset, 0);
        expect(h.peer.controlChannel.sent, [
          touch(0, 0, 100, 300),
          touch(2, 0, 100, 200),
          touch(2, 0, 100, 150),
          touch(1, 0, 100, 150),
        ]);
      } else {
        expect(scroll.offset, greaterThan(0));
        expect(h.peer.controlChannel.sent, isEmpty);
      }
    });
  }

  testWidgets('trackpad pan owns the ancestor arena and sends scroll', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final h = await pumpView(
      tester,
      wrap: (view) => ListView(
        controller: scroll,
        children: [
          Center(child: view),
          const SizedBox(height: 1200),
        ],
      ),
    );
    final position =
        tester.getTopLeft(find.byType(DeviceStreamView)) +
        const Offset(200, 300);
    await tester.sendEventToBinding(
      PointerPanZoomStartEvent(pointer: 404, position: position),
    );
    await tester.sendEventToBinding(
      PointerPanZoomUpdateEvent(
        pointer: 404,
        position: position,
        pan: const Offset(0, -100),
        panDelta: const Offset(0, -100),
      ),
    );
    await tester.sendEventToBinding(
      PointerPanZoomEndEvent(pointer: 404, position: position),
    );
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
    expect(h.peer.controlChannel.sent, [
      encodeScroll(
        videoWidth: 200,
        videoHeight: 400,
        x: 100,
        y: 300,
        hscrollTicks: 0,
        vscrollTicks: -1,
      ),
    ]);
  });

  testWidgets('mouse uses pointer -1', (tester) async {
    final h = await pumpView(tester);
    final origin = tester.getTopLeft(find.byType(DeviceStreamView));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: origin + const Offset(180, 130));
    await mouse.down(origin + const Offset(180, 130));
    await mouse.moveTo(origin + const Offset(190, 140));
    await tester.pump();
    await mouse.up();
    await mouse.removePointer();
    expect(h.peer.controlChannel.sent, [
      touch(0, -1, 80, 130),
      touch(2, -1, 90, 140),
      touch(1, -1, 90, 140),
    ]);
  });

  testWidgets('hover preserves buttons only on hover channel', (tester) async {
    final h = await pumpView(tester);
    final origin = tester.getTopLeft(find.byType(DeviceStreamView));
    await tester.sendEventToBinding(
      PointerHoverEvent(
        position: origin + const Offset(200, 150),
        buttons: 2,
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
    expect(h.peer.controlChannel.sent, isEmpty);
  });

  testWidgets('held mouse entering from letterbox remains hover', (
    tester,
  ) async {
    final h = await pumpView(tester);
    final origin = tester.getTopLeft(find.byType(DeviceStreamView));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: origin + const Offset(50, 50));
    await mouse.down(origin + const Offset(50, 50));
    await mouse.moveTo(origin + const Offset(220, 160));
    expect(
      h.peer.hoverChannel.sent.last,
      encodeHover(
        videoWidth: 200,
        videoHeight: 400,
        x: 120,
        y: 160,
        buttons: 1,
      ),
    );
    expect(h.peer.controlChannel.sent, isEmpty);
    await mouse.up();
    await mouse.removePointer();
  });

  testWidgets('wheel sends exact scroll bytes', (tester) async {
    final h = await pumpView(tester);
    final origin = tester.getTopLeft(find.byType(DeviceStreamView));
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: origin + const Offset(200, 150),
        scrollDelta: const Offset(100, -200),
        kind: PointerDeviceKind.mouse,
      ),
    );
    expect(h.peer.controlChannel.sent, [
      encodeScroll(
        videoWidth: 200,
        videoHeight: 400,
        x: 100,
        y: 150,
        hscrollTicks: -1,
        vscrollTicks: 2,
      ),
    ]);
    expect(h.peer.hoverChannel.sent, isEmpty);
  });

  testWidgets('hardware printable text has no release frame', (tester) async {
    final controller = DeviceStreamController();
    final h = await pumpView(tester, controller: controller);
    controller.showKeyboard();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'a');
    expect(h.peer.controlChannel.sent, [encodeText('a')]);
  });

  for (final (key, character, code) in [
    (LogicalKeyboardKey.enter, '\n', 66),
    (LogicalKeyboardKey.tab, '\t', 61),
    (LogicalKeyboardKey.backspace, '\b', 67),
    (LogicalKeyboardKey.escape, '\u001b', 111),
  ]) {
    testWidgets('native control character ${key.keyLabel} uses keycodes', (
      tester,
    ) async {
      final controller = DeviceStreamController();
      final h = await pumpView(tester, controller: controller);
      controller.showKeyboard();
      await tester.pump();
      await tester.sendKeyEvent(key, character: character);
      expect(h.peer.controlChannel.sent, press(code));
    });
  }

  testWidgets('scan-code-zero keys use logical fallback', (tester) async {
    final controller = DeviceStreamController();
    final h = await pumpView(tester, controller: controller);
    controller.showKeyboard();
    await tester.pump();
    for (final (keycode, character) in [(29, 'a'), (67, null), (66, null)]) {
      for (final type in ['keydown', 'keyup']) {
        await binding.defaultBinaryMessenger.handlePlatformMessage(
          SystemChannels.keyEvent.name,
          SystemChannels.keyEvent.codec.encodeMessage({
            'keymap': 'android',
            'type': type,
            'keyCode': keycode,
            'scanCode': 0,
            'character': type == 'keydown' ? character : null,
            'codePoint': character?.codeUnitAt(0) ?? 0,
            'plainCodePoint': character?.codeUnitAt(0) ?? 0,
          }),
          (_) {},
        );
      }
    }
    expect(h.peer.controlChannel.sent, [
      encodeText('a'),
      ...press(67),
      ...press(66),
    ]);
  });

  testWidgets('mapped fallback keys get down and up', (tester) async {
    final controller = DeviceStreamController();
    final h = await pumpView(tester, controller: controller);
    controller.showKeyboard();
    await tester.pump();
    await tester.sendKeyEvent(
      LogicalKeyboardKey.contextMenu,
      physicalKey: PhysicalKeyboardKey.contextMenu,
    );
    expect(h.peer.controlChannel.sent, press(82));
  });

  for (final character in <String?>[null, 'v', '\u0016']) {
    testWidgets('clipboard shortcut translates native character $character', (
      tester,
    ) async {
      final controller = DeviceStreamController();
      final h = await pumpView(tester, controller: controller);
      controller.showKeyboard();
      await tester.pump();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => call.method == 'Clipboard.getData'
            ? {'text': 'clipboard text'}
            : null,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV, character: character);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(h.peer.controlChannel.sent.where((b) => b[0] == 9), [
        encodeSetClipboard(text: 'clipboard text'),
      ]);
    });
  }

  testWidgets('normal IME keyboard supports composition, delete and action', (
    tester,
  ) async {
    final controller = DeviceStreamController();
    final h = await pumpView(tester, controller: controller);
    controller.showKeyboard();
    await tester.pump();
    expect(
      tester.testTextInput.setClientArgs!['inputType'],
      containsPair('name', 'TextInputType.text'),
    );
    expect(tester.testTextInput.setClientArgs!['autocorrect'], isFalse);
    expect(tester.testTextInput.setClientArgs!['enableSuggestions'], isFalse);
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
    tester.testTextInput.updateEditingValue(TextEditingValue.empty);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(h.peer.controlChannel.sent, [
      encodeText('日本'),
      ...press(67),
      ...press(66),
    ]);
  });

  testWidgets('hide finalizes owned composition', (tester) async {
    final controller = DeviceStreamController();
    final h = await pumpView(tester, controller: controller);
    controller.showKeyboard();
    await tester.pump();
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
  });

  testWidgets('system navigation sends exact pairs', (tester) async {
    final controller = DeviceStreamController();
    final h = await pumpView(tester, controller: controller);
    for (final key in DeviceSystemKey.values) {
      controller.sendSystemKey(key);
    }
    expect(h.peer.controlChannel.sent, [
      ...press(4),
      ...press(3),
      ...press(187),
    ]);
  });

  for (final change in ['control lost', 'session swap']) {
    testWidgets('$change cancels the old session touch', (tester) async {
      final controller = DeviceStreamController();
      final old = await pumpView(tester, controller: controller);
      controller.showKeyboard();
      await tester.pump();
      final origin = tester.getTopLeft(find.byType(DeviceStreamView));
      final finger = await tester.startGesture(origin + const Offset(200, 100));
      final next = change == 'session swap' ? Harness() : old;
      await pumpView(
        tester,
        harness: next,
        controller: controller,
        hasControl: change == 'session swap',
      );
      await finger.up();
      expect(old.peer.controlChannel.sent, [
        touch(0, 0, 100, 100),
        touch(3, 0, 100, 100),
      ]);
      if (change == 'session swap') {
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(text: '\u200bnew'),
        );
        await tester.pump();
        expect(next.peer.controlChannel.sent, [encodeText('new')]);
      }
    });
  }

  testWidgets('new keyed view owns controller after old view disposal', (
    tester,
  ) async {
    final controller = DeviceStreamController();
    final old = await pumpView(
      tester,
      controller: controller,
      viewKey: const ValueKey('old'),
      wrap: (view) =>
          AnimatedSwitcher(duration: const Duration(seconds: 1), child: view),
    );
    final next = Harness();
    await pumpView(
      tester,
      harness: next,
      controller: controller,
      viewKey: const ValueKey('new'),
      wrap: (view) =>
          AnimatedSwitcher(duration: const Duration(seconds: 1), child: view),
    );
    controller.sendSystemKey(DeviceSystemKey.home);
    await tester.pumpAndSettle();
    controller.sendSystemKey(DeviceSystemKey.back);
    expect(next.peer.controlChannel.sent, [...press(3), ...press(4)]);
    expect(old.peer.controlChannel.sent, isEmpty);
  });

  testWidgets('display only sends no input on any channel', (tester) async {
    final controller = DeviceStreamController();
    final h = await pumpView(tester, controller: controller, hasControl: false);
    final origin = tester.getTopLeft(find.byType(DeviceStreamView));
    final finger = await tester.startGesture(origin + const Offset(200, 150));
    await finger.moveTo(origin + const Offset(220, 170));
    await finger.cancel();
    await tester.sendEventToBinding(
      PointerHoverEvent(position: origin + const Offset(200, 150)),
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
  });

  for (final dispose in [false, true]) {
    testWidgets('${dispose ? 'dispose' : 'hide'} preserves the host keyboard', (
      tester,
    ) async {
      final controller = DeviceStreamController();
      final focus = FocusNode();
      addTearDown(focus.dispose);
      Widget host(Widget view) => Material(
        child: Column(
          children: [
            Expanded(child: view),
            TextField(focusNode: focus),
          ],
        ),
      );
      await pumpView(tester, controller: controller, wrap: host);
      controller.showKeyboard();
      await tester.pump();
      focus.requestFocus();
      await tester.pump();
      final client = tester.testTextInput.setClientArgs;
      tester.testTextInput.log.clear();
      if (dispose) {
        await tester.pumpWidget(MaterialApp(home: host(const SizedBox())));
      } else {
        controller.hideKeyboard();
      }
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
      expect(tester.testTextInput.setClientArgs, client);
      expect(tester.testTextInput.log.where(hideOrClear), isEmpty);
    });
  }
}
