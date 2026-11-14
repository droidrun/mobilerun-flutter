// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import '../core/stream_transports.dart';
import 'flutter_webrtc_peer.dart';
import 'web_socket_signalling.dart';

/// The production transports: `web_socket_channel` signalling and
/// `flutter_webrtc` peer connections.
StreamTransports defaultStreamTransports() => StreamTransports(
  signalling: const WebSocketSignallingConnector(),
  peers: FlutterWebRtcPeerFactory(),
);
