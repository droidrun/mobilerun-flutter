// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:mobilerun_flutter/mobilerun_flutter.dart';

/// Consumes the launch file once, including when its contents are invalid.
Future<StreamCredentials?> consumeCredentials(File file) async {
  if (!await file.exists()) return null;
  try {
    final Object? value = jsonDecode(await file.readAsString());
    if (value is! Map<String, dynamic>) throw const FormatException();
    final url = value['streamUrl'];
    final token = value['streamToken'];
    if (url is! String ||
        token is! String ||
        url.trim().isEmpty ||
        token.trim().isEmpty) {
      throw const FormatException();
    }
    return StreamCredentials(url: url.trim(), token: token.trim());
  } catch (_) {
    // Never include decoder input, file contents or transport errors in UI/logs.
    throw const FormatException('Invalid credentials file. Enter both fields.');
  } finally {
    await file.delete();
  }
}
