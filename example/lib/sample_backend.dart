// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:mobilerun_flutter/mobilerun_flutter.dart';

/// Immutable backend/device binding for one sample session. Holds no keys.
final class SampleBackend {
  SampleBackend({required this.baseUrl, required this.deviceId});

  final Uri baseUrl;
  final String deviceId;

  static const _requestTimeout = Duration(seconds: 10);

  Future<StreamCredentials?> credentials() async {
    final device = await _request('GET', '');
    final url = device['streamUrl'];
    if (url is! String || url.trim().isEmpty) return null;
    return StreamCredentials(url: url, tokenProvider: mintStreamKey);
  }

  Future<String> mintStreamKey() async {
    final result = await _request('POST', '/stream-key');
    final key = result['key'];
    if (key is! String) throw const FormatException('Backend request failed');
    return key;
  }

  Future<Map<String, dynamic>> _request(String method, String suffix) async {
    final client = HttpClient()..connectionTimeout = _requestTimeout;
    try {
      return await (() async {
        final path = '/api/v1/devices/${Uri.encodeComponent(deviceId)}$suffix';
        final request = await client.openUrl(method, baseUrl.resolve(path));
        request.followRedirects = false;
        request.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
        final response = await request.close();
        final expectedStatus = method == 'POST' ? 201 : 200;
        if (response.statusCode != expectedStatus) {
          throw const FormatException();
        }
        final Object? body = jsonDecode(
          await utf8.decoder.bind(response).join(),
        );
        if (body is! Map<String, dynamic>) throw const FormatException();
        return body;
      })().timeout(_requestTimeout);
    } catch (_) {
      throw const FormatException('Backend request failed');
    } finally {
      client.close(force: true);
    }
  }
}
