// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

/// Timings of the signalling exchange.
abstract final class SignallingTiming {
  SignallingTiming._();

  /// How long the signalling WebSocket may take to open.
  static const Duration wsOpenTimeout = Duration(seconds: 15);

  /// How long the `rtcConfiguration` reply may take after the socket opened.
  static const Duration rtcConfigTimeout = Duration(seconds: 15);

  /// How many `requestFrame` messages are sent once the control data channel
  /// opens.
  static const int requestFrameCount = 12;

  /// Gap between two `requestFrame` messages, the first going out at +0.
  static const Duration requestFrameInterval = Duration(milliseconds: 125);

  /// Gap between two `keepAlive` messages, armed at mount.
  static const Duration keepAliveInterval = Duration(seconds: 10);

  /// Window after a credential refresh in which non-terminal connection state
  /// dips are suppressed.
  static const Duration iceRestartGrace = Duration(seconds: 15);

  /// How long a screenshot request waits for its reply.
  static const Duration screenshotTimeout = Duration(seconds: 30);
}
