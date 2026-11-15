// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

/// Mobilerun device streaming SDK: the video/input view,
/// signalling message types, the reconnect controller and
/// [DeviceStreamSession], which connects to a cloud device (WebSocket
/// signalling and WebRTC) and recovers from failures.
library;

import 'src/core/device_stream_session.dart';

export 'src/core/device_stream_session.dart' show DeviceStreamSession;
export 'src/widgets/device_stream_view.dart'
    show DeviceStreamView, DeviceStreamController, DeviceSystemKey;
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
export 'src/approval/pending_approval.dart'
    show PendingApproval, ApprovalDecision;
export 'src/approval/task_approval_controller.dart'
    show
        TaskApprovalController,
        TaskApprovalState,
        TaskApprovalRequest,
        ApprovalSubscribe,
        ApprovalUnsubscribe;
export 'src/ui/stream_labels.dart' show StreamLabels;
export 'src/ui/task_approval_labels.dart' show TaskApprovalLabels;
export 'src/ui/stream_tokens.dart' show StreamTokens;
export 'src/ui/stream_theme.dart' show StreamTheme;
export 'src/ui/stream_status_pill.dart' show StreamStatusPill;
export 'src/ui/stream_lifecycle.dart' show StreamLifecycle;
export 'src/ui/task_approval_card.dart'
    show
        TaskApprovalCard,
        ApprovalActionsState,
        ApprovalActionsBuilder,
        defaultApprovalActions;

export 'src/ui/device_stream.dart'
    show
        DeviceStream,
        StreamNavigationBar,
        StreamOverlayState,
        StreamOverlayBuilder,
        StreamNavigationState,
        StreamNavigationBuilder,
        defaultStreamPlaceholder,
        defaultStreamUnavailable,
        defaultStreamNavigation;

export 'src/core/stream_stats.dart' show StreamStats;
