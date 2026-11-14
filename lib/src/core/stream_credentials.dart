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
/// It is called when the session starts, once per recovery cycle (the first
/// failure after a healthy stretch, and manual retries) and whenever the
/// server rejects the token. Return null when the credentials are not ready
/// yet (for example the device is still booting): the attempt then counts as
/// a failure and is retried with backoff. A throwing provider counts as a
/// failure too.
typedef StreamCredentialsProvider = Future<StreamCredentials?> Function();
