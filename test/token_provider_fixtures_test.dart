// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

// Local behaviour cases pending the approved shared credentials fixture tag.
// No fixture is hand-vendored and no cross-SDK conformance is claimed here.
import 'package:flutter_test/flutter_test.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';

import 'support/harness.dart';

void main() {
  for (final url in [
    'ws://stream.test/s',
    'ws://localhost.evil/s',
    'ws://localhost@evil.test/s',
    'wss:///s',
    'wss://stream.test:99999/s',
  ]) {
    test('insecure provider destination rejects before mint: $url', () async {
      var calls = 0;
      final h = Harness(
        credentials: (_) => StreamCredentials(
          url: url,
          token: 'static',
          tokenProvider: () async {
            calls++;
            return 'key';
          },
        ),
      );
      h.session.start();
      await pump();
      expect(calls, 0);
      expect(h.connector.uris, isEmpty);
      expect(h.statuses, [const StreamReconnecting(1)]);
      await h.session.close();
    });
  }
}
