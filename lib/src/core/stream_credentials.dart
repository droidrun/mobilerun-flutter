// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

/// Where and how to open the signalling WebSocket of one device stream.
final class StreamCredentials {
  /// Creates credentials for [url] with the bearer [token].
  const StreamCredentials({required this.url, required this.token});

  /// The signalling WebSocket URL (`wss://...`), without the token.
  final String url;

  /// The stream token. It is sent as the `token` query parameter; an empty
  /// token sends the URL unchanged.
  final String token;

  /// The URL to connect to: [url] with [token] as its `token` query parameter,
  /// replacing an existing one.
  Uri toWebSocketUri() {
    final uri = Uri.parse(url);
    if (token.isEmpty) return uri;
    return uri.replace(
      queryParameters: {...uri.queryParameters, 'token': token},
    );
  }

  // Never print the token.
  @override
  String toString() => 'StreamCredentials(url: $url)';
}

/// Supplies the credentials of a stream.
///
/// Before the first target, null, throwing and timed-out calls are polled every
/// three seconds without consuming the reconnect budget. Every call is bounded
/// by ReconnectPolicy.connectTimeout. Wake/retry can supersede a pending call.
/// After discovery, reconnects reuse the cached target while a heal or rejected
/// token refreshes credentials in the background. Null/failed refreshes retain
/// that target; connection failures exhaust the normal budget and show Retry.
typedef StreamCredentialsProvider = Future<StreamCredentials?> Function();
