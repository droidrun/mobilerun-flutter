// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

/// Mobilerun device streaming SDK: the control message encoders, the
/// signalling message types, the reconnect controller and
/// [DeviceStreamSession], which connects to a cloud device (WebSocket
/// signalling and WebRTC) and recovers from failures.
library;

import 'src/core/device_stream_session.dart';

export 'src/core/device_stream_session.dart' show DeviceStreamSession;
export 'src/widgets/device_stream.dart'
    show DeviceStream, DeviceStreamController, DeviceSystemKey;
export 'src/core/reconnect_controller.dart'
    show ReconnectController, ReconnectSnapshot, ReconnectStatus;
export 'src/core/reconnect_policy.dart' show ReconnectPolicy;
export 'src/core/scheduler.dart' show ScheduledTask, Scheduler, TimerScheduler;
export 'src/core/stream_config.dart' show StreamConfig;
export 'src/core/stream_exception.dart' show StreamSessionException;
export 'src/core/stream_credentials.dart'
    show StreamCredentials, StreamCredentialsProvider;
export 'src/core/stream_status.dart'
    show
        StreamConnected,
        StreamConnecting,
        StreamReconnecting,
        StreamStatus,
        StreamUnavailable,
        VideoSize;
export 'src/protocol/constants.dart'
    show AndroidKeys, AndroidMotionEvent, keyboardCodeMap;
export 'src/protocol/control_messages.dart'
    show
        encodeHover,
        encodeKeycode,
        encodeScroll,
        encodeSetClipboard,
        encodeText,
        encodeTouch;
export 'src/protocol/signalling.dart'
    show
        AnswerMessage,
        ClientCandidateMessage,
        ClientMessage,
        IceServer,
        KeepAliveMessage,
        OfferMessage,
        OpenUrlMessage,
        RequestFrameMessage,
        RequestRtcConfigurationMessage,
        RtcConfigurationMessage,
        ScreenshotErrorMessage,
        ScreenshotMessage,
        ScreenshotRequestMessage,
        ServerCandidateMessage,
        ServerMessage,
        SignallingPhase,
        SignallingStartupException,
        decodeServerMessage;
export 'src/protocol/stream_spec.dart' show DataChannelSpec, StreamDataChannels;
export 'src/protocol/stream_timing.dart' show SignallingTiming;
