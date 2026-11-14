// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';

void main() {
  test('the token becomes the token query parameter', () {
    const credentials = StreamCredentials(
      url: 'wss://stream.example.test/v1/devices/d/stream',
      token: 'abc+/=',
    );
    final uri = credentials.toWebSocketUri();
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

  test('toString never shows the token', () {
    const credentials = StreamCredentials(
      url: 'wss://x.test/s',
      token: 'secret',
    );
    expect(credentials.toString(), isNot(contains('secret')));
  });
}
