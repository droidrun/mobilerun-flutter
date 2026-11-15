// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobilerun_flutter/src/core/input/input_geometry.dart';
import 'package:mobilerun_flutter/src/core/input/key_input.dart';
import 'package:mobilerun_flutter/src/core/input/pointer_input.dart';
import 'package:mobilerun_flutter/src/core/input/scroll_input.dart';
import 'package:mobilerun_flutter/src/core/input/stream_text_input.dart';
import 'package:mobilerun_flutter/src/protocol/control_messages.dart';

import 'support/fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('fixture JSON preserves lone UTF-16 surrogate code units', () {
    final cases = readObjects('input/keys.json', 'cases');
    final keys = cases
        .expand((c) => c['events']! as List)
        .map((e) => asObject(e)['key']! as String);
    expect(
      keys.any((key) => key.length == 1 && key.codeUnitAt(0) == 0xd83d),
      isTrue,
    );
  });
  const counts = {
    'keys': 114,
    'ime': 21,
    'pointers': 18,
    'geometry': 25,
    'scroll': 21,
  };
  for (final entry in counts.entries) {
    final cases = readObjects('input/${entry.key}.json', 'cases');
    test(
      '${entry.key}: all ${entry.value} vectors registered',
      () => expect(cases.length, entry.value),
    );
    for (final c in cases) {
      test('${entry.key}: ${c['name']}', () {
        final sent = <Map<String, String>>[];
        void control(Uint8List bytes) =>
            sent.add({'channel': 'control', 'hex': toHex(bytes)});
        void hover(Uint8List bytes) =>
            sent.add({'channel': 'hover', 'hex': toHex(bytes)});
        double n(Map<String, Object?> m, String key) =>
            (m[key]! as num).toDouble();
        InputGeometry geometry({bool view = false}) {
          final width = c['video_width']! as int,
              height = c['video_height']! as int;
          return InputGeometry(
            Size(
              view ? n(c, 'view_width') : width.toDouble(),
              view ? n(c, 'view_height') : height.toDouble(),
            ),
            width,
            height,
            rotation: view ? c['rotation']! as int : 0,
          );
        }

        switch (entry.key) {
          case 'keys':
            final keys = KeyInput();
            for (final raw in c['events']! as List) {
              final e = asObject(raw);
              final result = keys.route(
                code: e['code']! as String,
                text: e['key']! as String,
                down: e['type'] == 'keydown',
                send: control,
                shift: e['shift']! as bool,
                alt: e['alt']! as bool,
                control: e['ctrl']! as bool,
                meta: e['meta']! as bool,
                capsLock: e['caps_lock']! as bool,
              );
              if (result == KeyRoute.paste &&
                  (e['clipboard']! as String).isNotEmpty) {
                control(
                  encodeSetClipboard(
                    text: e['clipboard']! as String,
                    paste: true,
                  ),
                );
              }
            }
          case 'ime':
            final input = StreamTextInput(active: () => true, send: control);
            void edit(String text, bool composing) => input.updateEditingValue(
              TextEditingValue(
                text: text,
                composing: composing
                    ? TextRange(start: 0, end: text.length)
                    : TextRange.empty,
              ),
            );
            switch (c['operation']) {
              case 'commit' || 'composition_end':
                edit('\u200b${c['text']! as String}', false);
              case 'composition_update':
                edit(c['text']! as String, true);
              case 'delete':
                final text = c['composition_text']! as String;
                if (text.isNotEmpty) edit(text, true);
                edit('', false);
            }
          case 'pointers':
            final input = PointerInput(control, sendHover: hover);
            final g = geometry();
            for (final raw in c['events']! as List) {
              final e = asObject(raw);
              final id = e['id']! as int, mouse = e['mouse']! as bool;
              final button = e['button']! as int;
              final point = Offset(n(e, 'x'), n(e, 'y'));
              switch (e['type']) {
                case 'down':
                  input.down(id, point, g, mouse: mouse, button: button);
                case 'move':
                  input.move(
                    id,
                    point,
                    mouse: mouse,
                    geometry: g,
                    buttons: e['buttons']! as int,
                  );
                  input.flushMoves();
                case 'up' || 'cancel':
                  input.up(
                    id,
                    mouse: mouse,
                    button: button,
                    cancelled: e['type'] == 'cancel',
                  );
              }
            }
          case 'geometry':
            final g = geometry(view: true);
            final point = g.map(Offset(n(c, 'x'), n(c, 'y')));
            if (c['expect'] == null) {
              expect(point, isNull);
            } else {
              final expected = asObject(c['expect']);
              expect(point, isNotNull);
              expect(g.videoWidth, expected['width']);
              expect(g.videoHeight, expected['height']);
              expect(point!.dx, closeTo(n(expected, 'x'), 1e-6));
              expect(point.dy, closeTo(n(expected, 'y'), 1e-6));
            }
            return;
          case 'scroll':
            routeScroll(
              geometry: geometry(),
              position: Offset(n(c, 'x'), n(c, 'y')),
              ticks: Offset(n(c, 'h'), n(c, 'v')),
              buttons: c['buttons']! as int,
              send: control,
            );
        }
        expect(sent, c['expect']);
      });
    }
  }
}
