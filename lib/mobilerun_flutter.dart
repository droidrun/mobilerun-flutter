// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

/// Headless core of the Mobilerun device streaming SDK: the control message
/// encoders, the signalling message types and the reconnect controller. It is
/// pure Dart and independent of any WebRTC or UI code.
library;

export 'src/core/reconnect_controller.dart'
    show ReconnectController, ReconnectSnapshot, ReconnectStatus;
export 'src/core/reconnect_policy.dart' show ReconnectPolicy, reconnectDelay;
export 'src/core/scheduler.dart' show ScheduledTask, Scheduler, TimerScheduler;
export 'src/protocol/constants.dart'
    show AndroidKeys, AndroidMotionEvent, ControlMessageType, keyboardCodeMap;
export 'src/protocol/control_messages.dart'
    show
        encodeHover,
        encodeKeycode,
        encodeScroll,
        encodeSetClipboard,
        encodeText,
        encodeTouch;
export 'src/protocol/signalling.dart';
export 'src/protocol/stream_timing.dart';
