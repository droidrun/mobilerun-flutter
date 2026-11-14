// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

// Generates lib/src/protocol/constants.dart from the vendored conformance
// fixture conformance/fixtures/constants.json.
//
// Usage (from the package root): dart run tool/generate_constants.dart

import 'dart:convert';
import 'dart:io';

const _inputPath = 'conformance/fixtures/constants.json';
const _outputPath = 'lib/src/protocol/constants.dart';

const _header = '''
// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

// GENERATED CODE - DO NOT MODIFY BY HAND.
// Source: conformance/fixtures/constants.json
// Regenerate with: dart run tool/generate_constants.dart
''';

/// A group of constants emitted as one class.
class _Group {
  const _Group(this.jsonKey, this.className, this.doc);

  final String jsonKey;
  final String className;
  final String doc;
}

const _groups = [
  _Group(
    'control_msg_type',
    'ControlMessageType',
    'Type byte of each binary control message.',
  ),
  _Group(
    'amotion_event',
    'AndroidMotionEvent',
    'Android `MotionEvent` actions and mouse button flags used by touch '
        'messages.',
  ),
  _Group(
    'android_keys',
    'AndroidKeys',
    'Android `KeyEvent` actions, meta state flags and key codes used by '
        'keycode messages.',
  ),
];

/// `KEYCODE_HOME` -> `keycodeHome`, `KEYCODE_BUTTON_L1` -> `keycodeButtonL1`.
String _camelCase(String name) {
  final parts = name.toLowerCase().split('_');
  final buffer = StringBuffer(parts.first);
  for (final part in parts.skip(1)) {
    buffer
      ..write(part[0].toUpperCase())
      ..write(part.substring(1));
  }
  return buffer.toString();
}

String _quote(String value) => "'${value.replaceAll("'", r"\'")}'";

/// Builds the source of constants.dart from the decoded fixture [json].
String generateConstants(Map<String, Object?> json) {
  final out = StringBuffer(_header)..writeln();
  for (final group in _groups) {
    final entries = (json[group.jsonKey]! as Map).cast<String, int>();
    final seen = <String>{};
    out
      ..writeln('/// ${group.doc}')
      ..writeln('abstract final class ${group.className} {')
      ..writeln('  ${group.className}._();')
      ..writeln();
    for (final entry in entries.entries) {
      final dartName = _camelCase(entry.key);
      if (!seen.add(dartName)) {
        throw StateError('name collision for ${entry.key} in ${group.jsonKey}');
      }
      out
        ..writeln('  /// `${entry.key}`.')
        ..writeln('  static const int $dartName = ${entry.value};')
        ..writeln();
    }
    out
      ..writeln('  /// Every constant of this class by its wire name.')
      ..writeln('  static const Map<String, int> values = {');
    for (final entry in entries.entries) {
      out.writeln('    ${_quote(entry.key)}: ${_camelCase(entry.key)},');
    }
    out
      ..writeln('  };')
      ..writeln('}')
      ..writeln();
  }
  final codeMap = (json['code_map']! as Map).cast<String, int>();
  out
    ..writeln(
      '/// Maps a W3C `KeyboardEvent.code` value to its Android key code.',
    )
    ..writeln('const Map<String, int> keyboardCodeMap = {');
  for (final entry in codeMap.entries) {
    out.writeln('  ${_quote(entry.key)}: ${entry.value},');
  }
  out.writeln('};');
  return out.toString();
}

Future<void> main() async {
  final json =
      jsonDecode(await File(_inputPath).readAsString()) as Map<String, Object?>;
  await File(_outputPath).writeAsString(generateConstants(json));
  final result = await Process.run('dart', ['format', _outputPath]);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  exit(result.exitCode);
}
