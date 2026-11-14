// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStream;

import 'stream_config.dart';

/// The connection state of a peer connection, as defined by W3C WebRTC.
enum PeerState {
  /// Created, nothing started.
  initial,

  /// Negotiating.
  connecting,

  /// Media can flow.
  connected,

  /// Temporarily lost; it may come back.
  disconnected,

  /// Terminal: the connection will not come back on its own.
  failed,

  /// Terminal: the connection was closed.
  closed,
}

/// The ready state of a data channel.
enum ChannelState {
  /// Opening.
  connecting,

  /// Messages can be sent.
  open,

  /// Closing.
  closing,

  /// Closed.
  closed,
}

/// Statistics of the decoded device video.
final class VideoStats {
  /// Creates statistics.
  const VideoStats({
    required this.width,
    required this.height,
    required this.framesDecoded,
  });

  /// Frame width in pixels.
  final int width;

  /// Frame height in pixels.
  final int height;

  /// Frames decoded so far on this connection.
  final int framesDecoded;
}

/// A locally or remotely gathered ICE candidate.
final class IceCandidateData {
  /// Creates a candidate.
  const IceCandidateData({
    required this.candidate,
    required this.sdpMid,
    required this.sdpMLineIndex,
  });

  /// The SDP candidate line.
  final String candidate;

  /// Media stream identification tag, may be null.
  final String? sdpMid;

  /// Index of the media description, may be null.
  final int? sdpMLineIndex;
}

/// An open signalling WebSocket. It exists only after the socket opened.
abstract interface class SignallingConnection {
  /// The received text frames. The stream is single-subscription (frames are
  /// held until it is listened to) and completes when the socket closes,
  /// whichever side closed it.
  Stream<String> get messages;

  /// Sends a text frame. Throws when the socket is closed.
  void send(String frame);

  /// Closes the socket. Never throws.
  Future<void> close();
}

/// Thrown by [SignallingConnector.connect] when the server refused the
/// WebSocket upgrade with an HTTP status, for example 401 for a rejected
/// token. Other failures to open are plain errors.
final class SignallingRejectedException implements Exception {
  /// Creates the exception for the HTTP [statusCode] of the refused upgrade.
  const SignallingRejectedException(this.statusCode);

  /// The HTTP status of the refused upgrade.
  final int statusCode;

  /// Whether the token (not the network) was refused.
  bool get isUnauthorized => statusCode == 401 || statusCode == 403;

  @override
  String toString() => 'SignallingRejectedException(status: $statusCode)';
}

/// Opens signalling WebSockets.
abstract interface class SignallingConnector {
  /// Opens a socket to [uri]. Completes once it is open; throws when it fails
  /// to open or closes before. The session applies the open timeout itself and
  /// closes a connection that completes after it gave up.
  Future<SignallingConnection> connect(Uri uri);
}

/// A data channel of a peer connection.
abstract interface class DataChannelTransport {
  /// The current ready state.
  ChannelState get state;

  /// Ready state changes.
  Stream<ChannelState> get states;

  /// Sends [data] as a binary message. Only called while [state] is
  /// [ChannelState.open].
  void send(Uint8List data);
}

/// One peer connection of a stream: recvonly audio and video, a negotiated
/// `control` channel (id 1) and a negotiated `hover` channel (id 2).
abstract interface class PeerTransport {
  /// Connection state changes. Events fire on this stream only after it is
  /// listened to, so the session listens before it creates the offer.
  Stream<PeerState> get connectionStates;

  /// Locally gathered ICE candidates, one per event. The end-of-candidates
  /// event is not reported.
  Stream<IceCandidateData> get localCandidates;

  /// The stream carrying the remote video track, emitted when the track
  /// arrives.
  Stream<MediaStream> get remoteVideoStreams;

  /// The reliable control channel.
  DataChannelTransport get control;

  /// The unreliable hover channel.
  DataChannelTransport get hover;

  /// Creates an offer, sets it as the local description and returns its SDP.
  /// [iceRestart] asks for new ICE credentials.
  Future<String> createLocalOffer({bool iceRestart = false});

  /// Sets the remote answer.
  Future<void> setRemoteAnswer(String sdp);

  /// Adds a remote candidate. Only called after the remote description is set.
  Future<void> addRemoteCandidate(IceCandidateData candidate);

  /// Replaces the ICE servers (a refreshed TURN credential). [iceServers] is
  /// the raw `iceServers` value of the `rtcConfiguration` message. Throws when
  /// the configuration is not accepted.
  Future<void> setIceServers(Object? iceServers);

  /// Mutes or unmutes the audio track (it stays negotiated and attached).
  /// Applies to a track that arrives later as well.
  void setAudioMuted(bool muted);

  /// Statistics of the decoded video, or null when no frame was decoded yet.
  Future<VideoStats?> readVideoStats();

  /// Closes the channels and the connection and releases everything.
  Future<void> close();
}

/// Creates peer connections.
abstract interface class PeerTransportFactory {
  /// Creates a peer connection for the raw `RTCConfiguration` the server sent.
  /// [muted] is the initial state of the audio track.
  Future<PeerTransport> create(
    Map<String, Object?> rtcConfiguration, {
    required StreamConfig config,
    required bool muted,
  });
}

/// The two transports a session needs.
final class StreamTransports {
  /// Creates the pair.
  const StreamTransports({required this.signalling, required this.peers});

  /// Opens the signalling WebSocket.
  final SignallingConnector signalling;

  /// Creates peer connections.
  final PeerTransportFactory peers;
}
