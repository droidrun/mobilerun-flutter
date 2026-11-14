// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Reads a JSON file below `conformance/fixtures` (tests run from the package
/// root).
Object? readFixture(String relativePath) =>
    jsonDecode(File('conformance/fixtures/$relativePath').readAsStringSync());

/// Reads a fixture file that is a JSON object.
Map<String, Object?> readFixtureObject(String relativePath) =>
    (readFixture(relativePath)! as Map).cast<String, Object?>();

/// The `cases` of a control fixture file.
List<Map<String, Object?>> readCases(String relativePath) =>
    (readFixtureObject(relativePath)['cases']! as List)
        .cast<Map>()
        .map((c) => c.cast<String, Object?>())
        .toList();

/// Lowercase hex of [bytes].
String toHex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Counts how many fixture cases a test file executed, so that a final test
/// can prove that every case in the fixture files was exercised.
final class CaseCounter {
  /// Number of cases run so far.
  int executed = 0;

  /// Records one executed case.
  void hit() => executed += 1;
}
