// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';
import 'support/input_vectors.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const counts = {
    'keys': 114,
    'ime': 21,
    'pointers': 18,
    'geometry': 25,
    'scroll': 21,
  };
  for (final entry in counts.entries) {
    final cases = readObjects('input/${entry.key}.json', 'cases');
    test(
      '${entry.key}: all ${entry.value} vectors registered',
      () => expect(cases.length, entry.value),
    );
    for (final c in cases) {
      test('${entry.key}: ${c['name']}', () {
        checkInputVector(entry.key, c);
      });
    }
  }
}
