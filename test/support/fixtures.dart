// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Casts a decoded JSON value to an object.
Map<String, Object?> asObject(Object? value) =>
    (value! as Map).cast<String, Object?>();

/// Reads a JSON file below `conformance/fixtures` (tests run from the package
/// root).
Object? readFixture(String relativePath) =>
    jsonDecode(File('conformance/fixtures/$relativePath').readAsStringSync());

/// Reads a fixture file that is a JSON object.
Map<String, Object?> readFixtureObject(String relativePath) =>
    asObject(readFixture(relativePath));

/// The objects of the list stored under [key] in a fixture file, for example
/// `readObjects('control/touch.json', 'cases')`.
List<Map<String, Object?>> readObjects(String relativePath, String key) =>
    (readFixtureObject(relativePath)[key]! as List).map(asObject).toList();

/// Lowercase hex of [bytes].
String toHex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
