// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'constants.dart';
import 'js_math.dart';

/// Largest magnitude a pointer id may have so that it stays exact on every
/// platform, including the web where integers are IEEE doubles.
const int _maxPointerIdMagnitude = 9007199254740992;

/// Size in bytes of a touch message.
const int _touchSize = 32;

/// Size in bytes of a scroll message.
const int _scrollSize = 21;

/// Size in bytes of a hover message.
const int _hoverSize = 17;

/// Size in bytes of a keycode message.
const int _keycodeSize = 14;

void _checkU8(String name, int value) =>
    RangeError.checkValueInInterval(value, 0, 0xff, name);

void _checkU16(String name, int value) =>
    RangeError.checkValueInInterval(value, 0, 0xffff, name);

/// Writes [value] as a signed 64-bit big-endian integer without relying on
/// `ByteData.setInt64`, which is unavailable on the web.
void _setInt64Big(ByteData data, int offset, int value) {
  const twoPow32 = 4294967296;
  var high = value ~/ twoPow32;
  var low = value - high * twoPow32;
  if (low < 0) {
    high -= 1;
    low += twoPow32;
  }
  data
    ..setUint32(offset, high.toUnsigned(32), Endian.big)
    ..setUint32(offset + 4, low, Endian.big);
}

/// Encodes a touch event (control message type 2, 32 bytes).
///
/// [x] and [y] are rounded half toward positive infinity. [pressure] is
/// `round(pressure * 0xffff)` stored in 16 bits, so `1.0` is `0xffff`.
/// [pointerId] is written big-endian; the mouse uses `-1`. [action] is one of
/// the [AndroidMotionEvent] actions and [actionButton] and [buttons] use the
/// [AndroidMotionEvent] button flags.
///
/// Throws a [RangeError] when [action] does not fit in a byte, when
/// [videoWidth] or [videoHeight] do not fit in 16 bits, or when [pointerId]
/// is beyond ±2^53. Throws an [ArgumentError] for a non-finite coordinate or
/// pressure.
Uint8List encodeTouch({
  required int action,
  required int pointerId,
  required int videoWidth,
  required int videoHeight,
  required num x,
  required num y,
  double pressure = 1.0,
  int actionButton = 0,
  int buttons = 0,
}) {
  _checkU8('action', action);
  _checkU16('videoWidth', videoWidth);
  _checkU16('videoHeight', videoHeight);
  RangeError.checkValueInInterval(
    pointerId,
    -_maxPointerIdMagnitude,
    _maxPointerIdMagnitude,
    'pointerId',
  );
  final data = ByteData(_touchSize)
    ..setUint8(0, ControlMessageType.injectTouchEvent)
    ..setUint8(1, action);
  _setInt64Big(data, 2, pointerId);
  data
    ..setInt32(10, jsRound(x).toSigned(32), Endian.little)
    ..setInt32(14, jsRound(y).toSigned(32), Endian.little)
    ..setUint16(18, videoWidth, Endian.little)
    ..setUint16(20, videoHeight, Endian.little)
    ..setUint16(22, jsRound(pressure * 0xffff).toUnsigned(16), Endian.little)
    ..setInt32(24, actionButton.toSigned(32), Endian.little)
    ..setInt32(28, buttons.toSigned(32), Endian.little);
  return data.buffer.asUint8List();
}

/// Encodes a normalised scroll value in [-1, 1] as scrcpy's 16-bit fixed
/// point number.
int _floatToI16FixedPoint(double value) {
  final clamped = math.max(-1.0, math.min(1.0, value));
  final scaled = jsRound(clamped * 0x8000);
  if (scaled >= 0x7fff) return 0x7fff;
  if (scaled < -0x8000) return -0x8000;
  return scaled;
}

/// Encodes a scroll event (control message type 3, 21 bytes).
///
/// [hscrollTicks] and [vscrollTicks] are wheel ticks (1.0 is one notch);
/// positive means left and up. Each is divided by 16, clamped to [-1, 1] and
/// converted to 16-bit fixed point. [buttons] is the bitmask of pressed
/// [AndroidMotionEvent] buttons.
///
/// Throws a [RangeError] when [videoWidth] or [videoHeight] do not fit in 16
/// bits and an [ArgumentError] for a non-finite coordinate or tick count.
Uint8List encodeScroll({
  required int videoWidth,
  required int videoHeight,
  required num x,
  required num y,
  required num hscrollTicks,
  required num vscrollTicks,
  int buttons = 0,
}) {
  _checkU16('videoWidth', videoWidth);
  _checkU16('videoHeight', videoHeight);
  final data = ByteData(_scrollSize)
    ..setUint8(0, ControlMessageType.injectScrollEvent)
    ..setInt32(1, jsRound(x).toSigned(32), Endian.little)
    ..setInt32(5, jsRound(y).toSigned(32), Endian.little)
    ..setUint16(9, videoWidth, Endian.little)
    ..setUint16(11, videoHeight, Endian.little)
    ..setInt16(13, _floatToI16FixedPoint(hscrollTicks / 16), Endian.little)
    ..setInt16(15, _floatToI16FixedPoint(vscrollTicks / 16), Endian.little)
    ..setInt32(17, buttons.toSigned(32), Endian.little);
  return data.buffer.asUint8List();
}

/// Encodes a mouse hover event (control message type 21, 17 bytes), the
/// cursor position while no button is held.
///
/// Throws a [RangeError] when [videoWidth] or [videoHeight] do not fit in 16
/// bits and an [ArgumentError] for a non-finite coordinate.
Uint8List encodeHover({
  required int videoWidth,
  required int videoHeight,
  required num x,
  required num y,
  int buttons = 0,
}) {
  _checkU16('videoWidth', videoWidth);
  _checkU16('videoHeight', videoHeight);
  final data = ByteData(_hoverSize)
    ..setUint8(0, ControlMessageType.injectMouseHoverEvent)
    ..setInt32(1, jsRound(x).toSigned(32), Endian.little)
    ..setInt32(5, jsRound(y).toSigned(32), Endian.little)
    ..setUint16(9, videoWidth, Endian.little)
    ..setUint16(11, videoHeight, Endian.little)
    ..setInt32(13, buttons.toSigned(32), Endian.little);
  return data.buffer.asUint8List();
}

/// Encodes a key event (control message type 0, 14 bytes).
///
/// [action] is [AndroidKeys.actionDown] or [AndroidKeys.actionUp], [keycode]
/// an [AndroidKeys] key code and [metaState] a combination of the
/// [AndroidKeys] meta flags.
///
/// Throws a [RangeError] when [action] does not fit in a byte.
Uint8List encodeKeycode({
  required int action,
  required int keycode,
  int repeat = 0,
  int metaState = 0,
}) {
  _checkU8('action', action);
  final data = ByteData(_keycodeSize)
    ..setUint8(0, ControlMessageType.injectKeycode)
    ..setUint8(1, action)
    ..setInt32(2, keycode.toSigned(32), Endian.little)
    ..setInt32(6, repeat.toSigned(32), Endian.little)
    ..setInt32(10, metaState.toSigned(32), Endian.little);
  return data.buffer.asUint8List();
}

/// Encodes a text injection (control message type 1, `5 + n` bytes): the
/// UTF-8 bytes of [text] behind a little-endian 32-bit length. The text is
/// encoded as is, without normalisation.
Uint8List encodeText({required String text}) {
  final bytes = utf8.encode(text);
  final data = ByteData(5 + bytes.length)
    ..setUint8(0, ControlMessageType.injectText)
    ..setInt32(1, bytes.length, Endian.little);
  return (data.buffer.asUint8List())..setRange(5, 5 + bytes.length, bytes);
}

/// Encodes a clipboard update (control message type 9, `14 + n` bytes): a
/// zero big-endian 64-bit sequence, the [paste] flag, then the UTF-8 bytes of
/// [text] behind a big-endian 32-bit length.
Uint8List encodeSetClipboard({required String text, bool paste = true}) {
  final bytes = utf8.encode(text);
  final data = ByteData(14 + bytes.length)
    ..setUint8(0, ControlMessageType.setClipboard)
    ..setUint8(9, paste ? 1 : 0)
    ..setUint32(10, bytes.length, Endian.big);
  return (data.buffer.asUint8List())..setRange(14, 14 + bytes.length, bytes);
}
