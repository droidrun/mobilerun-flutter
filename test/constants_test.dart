// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilerun_flutter/src/protocol/constants.dart';

import 'support/fixtures.dart';

void main() {
  final fixture = readFixtureObject('constants.json');

  Map<String, int> section(String key) =>
      (fixture[key]! as Map).cast<String, int>();

  test('control_msg_type equals the fixture', () {
    expect(ControlMessageType.values, section('control_msg_type'));
  });

  test('amotion_event equals the fixture', () {
    expect(AndroidMotionEvent.values, section('amotion_event'));
  });

  test('android_keys equals the fixture', () {
    expect(AndroidKeys.values, section('android_keys'));
  });

  test('code_map equals the fixture', () {
    expect(keyboardCodeMap, section('code_map'));
  });

  test('named constants carry the fixture values', () {
    expect(ControlMessageType.injectTouchEvent, 2);
    expect(ControlMessageType.injectMouseHoverEvent, 21);
    expect(AndroidMotionEvent.actionPointerDown, 5);
    expect(AndroidKeys.keycodeHome, 3);
    expect(AndroidKeys.metaCtrlOn, 4096);
    expect(AndroidKeys.dpadUp, 19);
    expect(AndroidKeys.enter, 66);
  });
}
