// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';

void main() {
  for (final url in [
    'wss://stream.test/a',
    'WSS://stream.test:443/a',
    'ws://localhost:3001/a',
    'ws://127.0.0.1/a',
    'ws://[::1]/a',
    'ws://[0:0:0:0:0:0:0:1]/a',
    'ws://[0::0001]/a',
  ]) {
    test('provider WSS and exact loopback policy allows $url', () {
      expect(StreamCredentials(url: url).allowsTokenProvider, isTrue);
    });
  }
  for (final url in [
    'ws://stream.test/a',
    'ws://localhost.evil/a',
    'ws://evil-localhost/a',
    'ws://localhost@evil.test/a',
    'ws://127.0.0.2/a',
    'https://stream.test/a',
    'wss:///a',
    'wss://',
    'not a url',
    'wss://stream.test:99999/a',
    'ws://[::2]/a',
    'wss://bad host/a',
  ]) {
    test('provider WSS and exact loopback policy denies $url', () {
      expect(StreamCredentials(url: url).allowsTokenProvider, isFalse);
    });
  }

  test('the token becomes the token query parameter', () {
    const credentials = StreamCredentials(
      url: 'wss://stream.example.test/v1/devices/d/stream',
      token: 'abc+/=',
    );
    final uri = credentials.toWebSocketUri();
    expect(
      uri.toString(),
      'wss://stream.example.test/v1/devices/d/stream?token=abc%2B%2F%3D',
    );
    expect(uri.scheme, 'wss');
    expect(uri.path, '/v1/devices/d/stream');
    expect(uri.queryParameters, {'token': 'abc+/='});
  });

  test('an existing token parameter is replaced, others are kept', () {
    const credentials = StreamCredentials(
      url: 'wss://stream.example.test/s?token=old&x=1',
      token: 'new',
    );
    expect(credentials.toWebSocketUri().queryParameters, {
      'token': 'new',
      'x': '1',
    });
  });

  test('an empty token leaves the URL unchanged', () {
    const credentials = StreamCredentials(
      url: 'wss://stream.example.test/s?x=1',
      token: '',
    );
    expect(credentials.toWebSocketUri().toString(), credentials.url);
  });

  test('toString redacts both URL and token', () {
    const credentials = StreamCredentials(
      url: 'wss://x.test/s',
      token: 'secret',
    );
    expect(
      credentials.toString(),
      'StreamCredentials(url: <redacted>, token: <redacted>)',
    );
  });
  test('a null token leaves the URL unchanged', () {
    const credentials = StreamCredentials(
      url: 'wss://x.test/s?token=old',
      token: null,
    );
    expect(credentials.toWebSocketUri().toString(), 'wss://x.test/s?token=old');
  });
}
