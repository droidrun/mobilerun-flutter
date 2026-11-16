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

import 'fixtures.dart';

typedef Send = void Function(Uint8List);
double number(Map<String, Object?> m, String key) =>
    (m[key]! as num).toDouble();
InputGeometry geometry(Map<String, Object?> c, {bool view = false}) {
  final width = c['video_width']! as int, height = c['video_height']! as int;
  return InputGeometry(
    Size(
      view ? number(c, 'view_width') : width.toDouble(),
      view ? number(c, 'view_height') : height.toDouble(),
    ),
    width,
    height,
    rotation: view ? c['rotation']! as int : 0,
  );
}

void keys(Map<String, Object?> c, Send send, Send hover) {
  final input = KeyInput();
  for (final raw in c['events']! as List) {
    final e = asObject(raw);
    final result = input.route(
      code: e['code']! as String,
      text: e['key']! as String,
      down: e['type'] == 'keydown',
      send: send,
      shift: e['shift']! as bool,
      alt: e['alt']! as bool,
      control: e['ctrl']! as bool,
      meta: e['meta']! as bool,
      capsLock: e['caps_lock']! as bool,
    );
    if (result == KeyRoute.paste && (e['clipboard']! as String).isNotEmpty) {
      send(encodeSetClipboard(text: e['clipboard']! as String, paste: true));
    }
  }
}

void ime(Map<String, Object?> c, Send send, Send hover) {
  final input = StreamTextInput(active: () => true, send: send);
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
      edit('​${c['text']! as String}', false);
    case 'composition_update':
      edit(c['text']! as String, true);
    case 'delete':
      final text = c['composition_text']! as String;
      if (text.isNotEmpty) edit(text, true);
      edit('', false);
  }
}

void pointers(Map<String, Object?> c, Send send, Send hover) {
  final input = PointerInput(send, sendHover: hover), g = geometry(c);
  for (final raw in c['events']! as List) {
    final e = asObject(raw);
    final id = e['id']! as int,
        mouse = e['mouse']! as bool,
        button = e['button']! as int;
    final point = Offset(number(e, 'x'), number(e, 'y'));
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
}

void scroll(Map<String, Object?> c, Send send, Send hover) => routeScroll(
  geometry: geometry(c),
  position: Offset(number(c, 'x'), number(c, 'y')),
  ticks: Offset(number(c, 'h'), number(c, 'v')),
  buttons: c['buttons']! as int,
  send: send,
);

void checkGeometry(Map<String, Object?> c) {
  final g = geometry(c, view: true);
  final point = g.map(Offset(number(c, 'x'), number(c, 'y')));
  if (c['expect'] == null) {
    expect(point, isNull);
    return;
  }
  final expected = asObject(c['expect']);
  expect(point, isNotNull);
  expect(g.videoWidth, expected['width']);
  expect(g.videoHeight, expected['height']);
  expect(point!.dx, closeTo(number(expected, 'x'), 1e-6));
  expect(point.dy, closeTo(number(expected, 'y'), 1e-6));
}

void checkInputVector(String kind, Map<String, Object?> c) {
  if (kind == 'geometry') {
    checkGeometry(c);
    return;
  }
  final sent = <Map<String, String>>[];
  void control(Uint8List bytes) =>
      sent.add({'channel': 'control', 'hex': toHex(bytes)});
  void hover(Uint8List bytes) =>
      sent.add({'channel': 'hover', 'hex': toHex(bytes)});
  final adapters = {
    'keys': keys,
    'ime': ime,
    'pointers': pointers,
    'scroll': scroll,
  };
  adapters[kind]!(c, control, hover);
  expect(sent, c['expect']);
}
