// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart' show internal;

/// Mints a fresh single-use key immediately before each signalling socket.
///
/// Callbacks must be non-blocking. Offload blocking or CPU work with `compute`
/// or `Isolate.run`. Pending futures have an independent 10-second deadline;
/// late completions are ignored without delaying teardown.
typedef StreamTokenProvider = Future<String> Function();

/// Where and how to open the signalling WebSocket of one device stream.
final class StreamCredentials {
  /// Creates credentials for [url] with the bearer [token].
  const StreamCredentials({required this.url, this.token, this.tokenProvider});

  /// The signalling WebSocket URL (`wss://...`), without the token.
  final String url;

  /// Legacy static credential path (deprecated): prefer [tokenProvider].
  /// A pasted single-use key cannot support reconnect.
  /// The stream token. It is sent as the `token` query parameter; a null or empty
  /// token sends the URL unchanged.
  final String? token;

  /// Called once per new socket. Failure, blank output or timeout never falls
  /// back to [token] or an embedded URL token. Nonblank output is used verbatim.
  final StreamTokenProvider? tokenProvider;

  /// Provider destinations require WSS, or WS to an exact loopback host.
  @internal
  bool get allowsTokenProvider {
    try {
      final uri = Uri.parse(url);
      final host = uri.host;
      final validHost = host.isNotEmpty && !host.contains('%');
      if (!validHost || uri.port > 65535) return false;
      if (uri.scheme == 'wss') return true;
      var loopback = host == 'localhost' || host == '127.0.0.1';
      if (host.contains(':')) {
        final bytes = Uri.parseIPv6Address(host);
        loopback = bytes.take(15).every((byte) => byte == 0) && bytes.last == 1;
      }
      return uri.scheme == 'ws' && loopback;
    } on FormatException {
      return false;
    }
  }

  /// The URL to connect to: [url] with [token] as its `token` query parameter,
  /// replacing an existing one.
  Uri toWebSocketUri() {
    final uri = Uri.parse(url);
    final token = this.token;
    if (token == null || token.isEmpty) return uri;
    return uri.replace(
      queryParameters: {...uri.queryParameters, 'token': token},
    );
  }

  // Never print the URL or token.
  @override
  String toString() => 'StreamCredentials(url: <redacted>, token: <redacted>)';
}

/// Supplies the credentials of a stream.
///
/// Before the first target, null, throwing and timed-out calls are polled every
/// three seconds without consuming the reconnect budget. Every call is bounded
/// by 45 seconds. Wake/retry can supersede a pending call.
/// After discovery, reconnects reuse the cached target while a heal or rejected
/// token refreshes credentials in the background. Null/failed refreshes retain
/// that target; connection failures exhaust the normal budget and show Retry.
typedef StreamCredentialsProvider = Future<StreamCredentials?> Function();
