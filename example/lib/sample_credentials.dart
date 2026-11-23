// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:mobilerun_flutter/mobilerun_flutter.dart';

import 'sample_backend.dart';

/// Credential-free helper binding or a device token (legacy) diagnostic target.
final class SampleLaunch {
  const SampleLaunch({this.backend, this.credentials});
  final SampleBackend? backend;
  final StreamCredentials? credentials;
}

/// Consumes the launch file once, including when its contents are invalid.
Future<SampleLaunch?> consumeLaunch(File file) async {
  if (!await file.exists()) return null;
  try {
    final Object? value = jsonDecode(await file.readAsString());
    if (value is! Map<String, dynamic>) throw const FormatException();
    final helper = value['helperBaseUrl'];
    final deviceId = value['deviceId'];
    if (helper != null || deviceId != null) {
      if (helper is! String || deviceId is! String || deviceId.trim().isEmpty) {
        throw const FormatException();
      }
      final uri = Uri.parse(helper);
      final loopback =
          uri.host == 'localhost' ||
          uri.host == '127.0.0.1' ||
          uri.host == '::1';
      final validScheme =
          uri.scheme == 'https' || (uri.scheme == 'http' && loopback);
      final validBase =
          validScheme && uri.host.isNotEmpty && uri.userInfo.isEmpty;
      if (!validBase || uri.hasQuery || uri.hasFragment) {
        throw const FormatException();
      }
      return SampleLaunch(
        backend: SampleBackend(baseUrl: uri, deviceId: deviceId),
      );
    }
    final url = value['streamUrl'];
    final token = value['streamToken'];
    if (url is! String ||
        token is! String ||
        url.trim().isEmpty ||
        token.trim().isEmpty) {
      throw const FormatException();
    }
    return SampleLaunch(
      credentials: StreamCredentials(url: url.trim(), token: token.trim()),
    );
  } catch (_) {
    // Never include decoder input, file contents or transport errors in UI/logs.
    throw const FormatException();
  } finally {
    await file.delete();
  }
}
