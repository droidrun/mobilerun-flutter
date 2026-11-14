// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

String _requireString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw FormatException('"$key" must be a string', json);
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null || value is String) return value as String?;
  throw FormatException('"$key" must be a string or null', json);
}

int? _optionalInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null || value is int) return value as int?;
  throw FormatException('"$key" must be an integer or null', json);
}

String _typeOf(Map<String, Object?> json) {
  final type = json['type'];
  if (type is String) return type;
  throw FormatException('"type" must be a string', json);
}

/// A signalling message the client sends to the server as a JSON text frame.
sealed class ClientMessage {
  const ClientMessage();

  /// Parses a client message from its decoded JSON object.
  ///
  /// Throws a [FormatException] when `type` is unknown or a field is missing
  /// or has the wrong type.
  factory ClientMessage.fromJson(Map<String, Object?> json) {
    switch (_typeOf(json)) {
      case RequestRtcConfigurationMessage.messageType:
        return RequestRtcConfigurationMessage(
          sessionId: _requireString(json, 'sessionId'),
        );
      case OfferMessage.messageType:
        return OfferMessage(
          sdp: _requireString(json, 'sdp'),
          sessionId: _requireString(json, 'sessionId'),
        );
      case ClientCandidateMessage.messageType:
        return ClientCandidateMessage(
          candidate: _requireString(json, 'candidate'),
          sdpMid: _optionalString(json, 'sdpMid'),
          sdpMLineIndex: _optionalInt(json, 'sdpMLineIndex'),
          sessionId: _requireString(json, 'sessionId'),
        );
      case KeepAliveMessage.messageType:
        return KeepAliveMessage(sessionId: _requireString(json, 'sessionId'));
      case RequestFrameMessage.messageType:
        return RequestFrameMessage(
          sessionId: _requireString(json, 'sessionId'),
        );
      case OpenUrlMessage.messageType:
        return OpenUrlMessage(
          url: _requireString(json, 'url'),
          sessionId: _requireString(json, 'sessionId'),
        );
      case ScreenshotRequestMessage.messageType:
        return ScreenshotRequestMessage(id: _requireString(json, 'id'));
    }
    throw FormatException('unknown client message type', json);
  }

  /// The wire `type` of this message.
  String get type;

  /// The JSON object sent on the wire.
  Map<String, Object?> toJson();

  /// The JSON text frame sent on the wire.
  String encode() => jsonEncode(toJson());
}

/// First message after the WebSocket opens: asks for the ICE configuration.
final class RequestRtcConfigurationMessage extends ClientMessage {
  /// Creates the request for [sessionId].
  const RequestRtcConfigurationMessage({required this.sessionId});

  /// Wire `type` value.
  static const String messageType = 'requestRtcConfiguration';

  /// The streaming session id.
  final String sessionId;

  @override
  String get type => messageType;

  @override
  Map<String, Object?> toJson() => {
    'type': messageType,
    'sessionId': sessionId,
    // Always advertised: opts in to mid-session credential refreshes.
    'supportsLiveRtcRefresh': true,
  };
}

/// SDP offer, sent once after the peer connection is set up and again for
/// every mid-session ICE restart.
final class OfferMessage extends ClientMessage {
  /// Creates an offer carrying [sdp].
  const OfferMessage({required this.sdp, required this.sessionId});

  /// Wire `type` value.
  static const String messageType = 'offer';

  /// The session description.
  final String sdp;

  /// The streaming session id.
  final String sessionId;

  @override
  String get type => messageType;

  @override
  Map<String, Object?> toJson() => {
    'type': messageType,
    'sdp': sdp,
    'sessionId': sessionId,
  };
}

/// A locally gathered ICE candidate, sent as soon as it is gathered. The
/// end-of-candidates event is not sent.
final class ClientCandidateMessage extends ClientMessage {
  /// Creates a candidate message.
  const ClientCandidateMessage({
    required this.candidate,
    required this.sdpMid,
    required this.sdpMLineIndex,
    required this.sessionId,
  });

  /// Wire `type` value.
  static const String messageType = 'candidate';

  /// The SDP candidate line.
  final String candidate;

  /// Media stream identification tag, may be null.
  final String? sdpMid;

  /// Index of the media description, may be null.
  final int? sdpMLineIndex;

  /// The streaming session id.
  final String sessionId;

  @override
  String get type => messageType;

  @override
  Map<String, Object?> toJson() => {
    'type': messageType,
    'candidate': candidate,
    'sdpMid': sdpMid,
    'sdpMLineIndex': sdpMLineIndex,
    'sessionId': sessionId,
  };
}

/// Heartbeat, sent every 10 s while the page is visible and the socket open.
final class KeepAliveMessage extends ClientMessage {
  /// Creates a heartbeat for [sessionId].
  const KeepAliveMessage({required this.sessionId});

  /// Wire `type` value.
  static const String messageType = 'keepAlive';

  /// The streaming session id.
  final String sessionId;

  @override
  String get type => messageType;

  @override
  Map<String, Object?> toJson() => {
    'type': messageType,
    'sessionId': sessionId,
  };
}

/// Asks the encoder for a fresh frame; sent repeatedly when the control data
/// channel opens.
final class RequestFrameMessage extends ClientMessage {
  /// Creates a frame request for [sessionId].
  const RequestFrameMessage({required this.sessionId});

  /// Wire `type` value.
  static const String messageType = 'requestFrame';

  /// The streaming session id.
  final String sessionId;

  @override
  String get type => messageType;

  @override
  Map<String, Object?> toJson() => {
    'type': messageType,
    'sessionId': sessionId,
  };
}

/// Asks the device to open a URL; sent once when the control data channel
/// opens, only if the embedding app supplied one.
final class OpenUrlMessage extends ClientMessage {
  /// Creates a message carrying the already decoded [url].
  const OpenUrlMessage({required this.url, required this.sessionId});

  /// Creates a message from the URL as supplied by the embedding app.
  ///
  /// The input is percent-decoded as a URI component; when decoding fails the
  /// input is used unchanged.
  factory OpenUrlMessage.fromInput({
    required String input,
    required String sessionId,
  }) {
    String url;
    try {
      url = Uri.decodeComponent(input);
    } on ArgumentError {
      url = input;
    } on FormatException {
      url = input;
    }
    return OpenUrlMessage(url: url, sessionId: sessionId);
  }

  /// Wire `type` value.
  static const String messageType = 'openUrl';

  /// The URL to open.
  final String url;

  /// The streaming session id.
  final String sessionId;

  @override
  String get type => messageType;

  @override
  Map<String, Object?> toJson() => {
    'type': messageType,
    'url': url,
    'sessionId': sessionId,
  };
}

/// Requests a screenshot. The reply carries the same [id]. This message has
/// no session id.
final class ScreenshotRequestMessage extends ClientMessage {
  /// Creates a request with the client-chosen correlation [id].
  const ScreenshotRequestMessage({required this.id});

  /// Wire `type` value.
  static const String messageType = 'screenshot';

  /// Correlation id echoed by the reply.
  final String id;

  @override
  String get type => messageType;

  @override
  Map<String, Object?> toJson() => {'type': messageType, 'id': id};
}

/// A signalling message the client receives from the server as a JSON text
/// frame.
sealed class ServerMessage {
  const ServerMessage();

  /// Parses a server message from its decoded JSON object.
  ///
  /// Throws a [FormatException] when `type` is unknown or a field is missing
  /// or has the wrong type. Use [decodeServerMessage] to apply the
  /// phase-dependent ignore rules to a received text frame.
  factory ServerMessage.fromJson(Map<String, Object?> json) {
    switch (_typeOf(json)) {
      case AnswerMessage.messageType:
        return AnswerMessage(sdp: _requireString(json, 'sdp'));
      case ServerCandidateMessage.messageType:
        return ServerCandidateMessage(
          candidate: _requireString(json, 'candidate'),
          sdpMid: _optionalString(json, 'sdpMid'),
          sdpMLineIndex: _optionalInt(json, 'sdpMLineIndex'),
        );
      case RtcConfigurationMessage.messageType:
        final configuration = json['rtcConfiguration'];
        if (configuration is! Map) {
          throw FormatException('"rtcConfiguration" must be an object', json);
        }
        return RtcConfigurationMessage(
          rtcConfiguration: configuration.cast<String, Object?>(),
        );
      case ScreenshotMessage.messageType:
        return ScreenshotMessage(
          id: _requireString(json, 'id'),
          dataUri: _requireString(json, 'dataUri'),
        );
      case ScreenshotErrorMessage.messageType:
        return ScreenshotErrorMessage(
          id: _requireString(json, 'id'),
          message: _requireString(json, 'message'),
        );
    }
    throw FormatException('unknown server message type', json);
  }

  /// The wire `type` of this message.
  String get type;

  /// The JSON object as received on the wire.
  Map<String, Object?> toJson();

  /// The JSON text frame as received on the wire.
  String encode() => jsonEncode(toJson());
}

/// SDP answer to the latest offer, initial or ICE restart.
final class AnswerMessage extends ServerMessage {
  /// Creates an answer carrying [sdp].
  const AnswerMessage({required this.sdp});

  /// Wire `type` value.
  static const String messageType = 'answer';

  /// The session description.
  final String sdp;

  @override
  String get type => messageType;

  @override
  Map<String, Object?> toJson() => {'type': messageType, 'sdp': sdp};
}

/// A remote ICE candidate, buffered until the remote description is set.
final class ServerCandidateMessage extends ServerMessage {
  /// Creates a candidate message.
  const ServerCandidateMessage({
    required this.candidate,
    required this.sdpMid,
    required this.sdpMLineIndex,
  });

  /// Wire `type` value.
  static const String messageType = 'candidate';

  /// The SDP candidate line.
  final String candidate;

  /// Media stream identification tag, may be null.
  final String? sdpMid;

  /// Index of the media description, may be null.
  final int? sdpMLineIndex;

  @override
  String get type => messageType;

  @override
  Map<String, Object?> toJson() => {
    'type': messageType,
    'candidate': candidate,
    'sdpMid': sdpMid,
    'sdpMLineIndex': sdpMLineIndex,
  };
}

/// An ICE server entry of an [RtcConfigurationMessage].
final class IceServer {
  /// Creates an ICE server entry.
  const IceServer({required this.urls, this.username, this.credential});

  /// Parses an entry whose `urls` is a string or a list of strings.
  ///
  /// Throws a [FormatException] for any other shape.
  factory IceServer.fromJson(Map<String, Object?> json) {
    final urls = json['urls'];
    final List<String> parsed;
    if (urls is String) {
      parsed = [urls];
    } else if (urls is List && urls.every((url) => url is String)) {
      parsed = urls.cast<String>();
    } else {
      throw FormatException('"urls" must be a string or list of strings', json);
    }
    return IceServer(
      urls: parsed,
      username: _optionalString(json, 'username'),
      credential: _optionalString(json, 'credential'),
    );
  }

  /// STUN and TURN URLs of this server.
  final List<String> urls;

  /// TURN user name, if any.
  final String? username;

  /// TURN credential, if any.
  final String? credential;
}

/// ICE configuration. The first one is the reply to
/// [RequestRtcConfigurationMessage]; later ones are mid-session credential
/// refreshes. Which of the two it is depends on the connection phase, not on
/// the content.
final class RtcConfigurationMessage extends ServerMessage {
  /// Creates a message around the raw [rtcConfiguration] object.
  const RtcConfigurationMessage({required this.rtcConfiguration});

  /// Wire `type` value.
  static const String messageType = 'rtcConfiguration';

  /// The raw `RTCConfiguration` object, kept as received so that it can be
  /// handed to the peer connection unchanged.
  final Map<String, Object?> rtcConfiguration;

  /// The typed `iceServers` entries, or null when the field is absent (a
  /// refresh without it is ignored).
  ///
  /// Throws a [FormatException] when the field is present but malformed.
  List<IceServer>? get iceServers {
    final servers = rtcConfiguration['iceServers'];
    if (servers == null) return null;
    if (servers is! List) {
      throw FormatException('"iceServers" must be a list', rtcConfiguration);
    }
    return [
      for (final server in servers)
        if (server is Map)
          IceServer.fromJson(server.cast<String, Object?>())
        else
          throw FormatException('"iceServers" entries must be objects', server),
    ];
  }

  @override
  String get type => messageType;

  @override
  Map<String, Object?> toJson() => {
    'type': messageType,
    'rtcConfiguration': rtcConfiguration,
  };
}

/// Successful screenshot reply.
final class ScreenshotMessage extends ServerMessage {
  /// Creates a reply for request [id].
  const ScreenshotMessage({required this.id, required this.dataUri});

  /// Wire `type` value.
  static const String messageType = 'screenshot';

  /// Correlation id of the pending request.
  final String id;

  /// The image as a data URI, for example `data:image/png;base64,...`.
  final String dataUri;

  @override
  String get type => messageType;

  @override
  Map<String, Object?> toJson() => {
    'type': messageType,
    'id': id,
    'dataUri': dataUri,
  };
}

/// Failed screenshot reply.
final class ScreenshotErrorMessage extends ServerMessage {
  /// Creates a failure reply for request [id].
  const ScreenshotErrorMessage({required this.id, required this.message});

  /// Wire `type` value.
  static const String messageType = 'screenshotError';

  /// Correlation id of the pending request.
  final String id;

  /// Human readable failure reason.
  final String message;

  @override
  String get type => messageType;

  @override
  Map<String, Object?> toJson() => {
    'type': messageType,
    'id': id,
    'message': message,
  };
}

/// The connection phase that decides how an unusable server frame is treated.
enum SignallingPhase {
  /// The `requestRtcConfiguration` message was sent and its reply is awaited.
  /// Only an `rtcConfiguration` message is acted on; text that is not valid
  /// JSON fails startup.
  awaitingRtcConfiguration,

  /// The peer connection and the general message handler exist. Frames that
  /// are not valid JSON, have an unknown type or are malformed are dropped.
  active,
}

/// Thrown by [decodeServerMessage] when a frame that is not valid JSON
/// arrives while [SignallingPhase.awaitingRtcConfiguration]; the connection
/// attempt has failed.
final class SignallingStartupException implements Exception {
  /// Creates the exception for the offending [text].
  const SignallingStartupException(this.text);

  /// The frame that could not be parsed.
  final String text;

  @override
  String toString() =>
      'SignallingStartupException: reply is not valid JSON: $text';
}

/// Applies the phase-dependent rules to a received server text frame.
///
/// Returns the parsed message, or null when the frame is ignored:
///
/// * While [SignallingPhase.awaitingRtcConfiguration], every valid JSON frame
///   other than a well-formed `rtcConfiguration` is ignored.
/// * While [SignallingPhase.active], frames that are not valid JSON, not an
///   object, of an unknown type or missing required fields are dropped.
///
/// Throws a [SignallingStartupException] for text that is not valid JSON
/// while [SignallingPhase.awaitingRtcConfiguration].
ServerMessage? decodeServerMessage(
  String text, {
  required SignallingPhase phase,
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    if (phase == SignallingPhase.awaitingRtcConfiguration) {
      throw SignallingStartupException(text);
    }
    return null;
  }
  if (decoded is! Map) return null;
  final json = decoded.cast<String, Object?>();
  if (phase == SignallingPhase.awaitingRtcConfiguration &&
      json['type'] != RtcConfigurationMessage.messageType) {
    return null;
  }
  try {
    return ServerMessage.fromJson(json);
  } on FormatException {
    return null;
  }
}
