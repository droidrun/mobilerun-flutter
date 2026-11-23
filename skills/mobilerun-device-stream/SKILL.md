---
name: mobilerun-device-stream
description: Integrate a live Mobilerun device into a Flutter partner app with server-minted stream tokens, connection recovery, and white-label UI.
---

# Mobilerun device stream for Flutter

## When to use

Use for embedding live device video and remote input with `mobilerun_flutter` on
Android or iOS. Read [stream keys](../../doc/stream-keys.md) and
[default UI](../../doc/default-ui.md) for the full branch-specific behavior.

## Backend: mint one token per connect

Authenticate the app user and authorize access to the requested device on your
backend before minting. Call `POST https://api.mobilerun.ai/v1/identity/stream-keys`
with `Authorization: Bearer <MOBILERUN_API_KEY>` and JSON
`{deviceId, ttlSeconds, allowedOrigins?}`. Keep `MOBILERUN_API_KEY` in the server
environment only. The response is `{key, keyId, expiresAt}`; return only `key` to
the app, without caching it. Tokens start with `dr_st_`, are single-use, and
expire after 120 seconds by default. Optional `allowedOrigins` binds browser use
to listed site origins; it does not replace user/device authorization.

Dart server example (never include this server code in the Flutter app):

```dart
import 'dart:convert';
import 'dart:io';

Future<String> mintStreamKey(String authorizedDeviceId) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.parse('https://api.mobilerun.ai/v1/identity/stream-keys'),
    );
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${Platform.environment['MOBILERUN_API_KEY']!}',
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'deviceId': authorizedDeviceId,
      'ttlSeconds': 120,
      // For browser consumers: 'allowedOrigins': ['https://partner.example'],
    }));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200 && response.statusCode != 201) {
      // On 422, inspect the response's `issues` for invalid request fields.
      throw HttpException('Stream key mint failed: ${response.statusCode}');
    }
    return (jsonDecode(body) as Map<String, dynamic>)['key'] as String;
  } finally {
    client.close();
  }
}
```

## Client: provide a fresh token for every socket

`StreamCredentials.tokenProvider` is a `Future<String> Function()`, called before
**every** connection attempt, including reconnects. It must request a newly
minted key from your authenticated backend each time; never cache or reuse a key.
The outer `credentials` callback discovers the target and is not a substitute
for the per-connect token provider.

```dart
import 'package:flutter/material.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';

// mintFromBackend is app-supplied: an authenticated call to your backend,
// returning the newly minted key for this device (not a Mobilerun SDK method).
DeviceStreamSession createSession(
  String deviceId,
  Future<String> Function(String deviceId) mintFromBackend,
) {
  return DeviceStreamSession(
    credentials: () async => StreamCredentials(
      url: 'wss://api.mobilerun.ai/v1/devices/$deviceId/stream',
      tokenProvider: () => mintFromBackend(deviceId),
    ),
    onError: (error) {
      debugPrint('stream ${error.reason.code} attempt ${error.attempt} '
          'final=${error.isFinal}');
    },
  )..start();
}

Widget streamPanel(DeviceStreamSession session) => Expanded(
  child: StreamTheme(
    tokens: const StreamTokens().copyWith(
      primary: const Color(0xff005b50),
      primaryForeground: Colors.white,
      radius: 10,
    ),
    child: DeviceStream(
      session: session,
      labels: const StreamLabels(
        connecting: 'Starting device',
        unavailable: 'Phone unavailable',
        retry: 'Try again',
      ),
    ),
  ),
);
```

Create the session once in the owning widget's lifecycle, outside `build`.
Place `streamPanel` inside a `Column` or `Row` with bounded space. The app owns
`start()` and `close()`; call `session.close()` when finished. Recreate the session
when switching devices. The SDK appends and encodes the `token` query parameter;
supply a token-free `wss` URL. Provider mode permits insecure `ws` only on exact
loopback hosts for local development.

## Errors and recovery

`onError` receives `StreamError` with `reason`, `message`, `attempt` (1-based) and
`isFinal`. Use `error.reason.code` for the shared wire-style names below.
`isFinal` is Flutter's name for the contract's `final`: retries have stopped,
status is `StreamUnavailable`, and the default Retry UI calls `session.retry()`.
Allow bounded SDK backoff; avoid adding an automatic retry loop around it.

| Reason code | Meaning and action |
| --- | --- |
| `credentials_unavailable` | Provider threw, returned blank output, or exceeded 10 seconds. Fix backend authentication, availability or response parsing. Keep the callback non-blocking. |
| `token_rejected` | Upgrade exposed HTTP 401. Mint a fresh key; check expiry, prior use, revocation, device binding and origin restrictions. |
| `connection_refused` | Socket failed before opening, including rejected credentials where no status is exposed. Check host, device, origin and network; HTTP 403 also lands here. |
| `disconnected` | An open session dropped, including the 30-minute server session cap. Let the SDK reconnect with a fresh key. |
| `device_unavailable` | Reserved for a server offline/not-ready signal; this branch's protocol does not emit it yet. If introduced, restore device readiness before retrying. |
| `unknown` | Other failures such as watchdog or negotiation timeout. Inspect the sanitized message and network/device state. |

A failed token provider never falls back to a static token or a token embedded in
the URL. Late results after timeout or close do not open sockets.

## Labels and theming

`DeviceStream.labels` takes `StreamLabels` with English defaults. Override
`connecting`, `reconnecting`, `disconnected`, `reconnectingAttempt`, `unavailable`,
`retry`, `back`, `home` and `recent`. Preserve `{attempt}` and `{max}` in
`reconnectingAttempt` templates. `disconnected` labels recovery after an open
session dropped.

Wrap widgets in `StreamTheme`. `StreamTokens().copyWith(...)` supports
`background`, `foreground`, `card`, `cardForeground`, `muted`, `mutedForeground`,
`border`, `ring`, `primary`, `primaryForeground`, `accent`, `accentForeground`,
`destructive`, `radius` and `typography`. Keep foreground/background pairs readable.
Light is the default independently of the host Material theme; use
`tokens: StreamTokens.dark` for fixed dark styling or `followSystem: true` to
follow system brightness (with optional `darkTokens`).

For custom chrome, use `DeviceStream.placeholderBuilder`, `unavailableBuilder`
and `navigationBuilder`, or use `DeviceStreamView` for video/input with your own UI.
The built-in stream UI displays no logo or product name.

## Security rules

- Never ship a Mobilerun API key in app code, assets or client configuration.
- Treat a stream token as a bearer capability for viewing and controlling one
  device. It can be redeemed once, before its first connect or expiry; consuming
  it opens the session, rather than ending control at connect time.
- Never log, persist, or share stream tokens or token-bearing URLs. Protect your
  mint endpoint with your app's authentication and device authorization.
- `StreamCredentials.token` is a deprecated static-token exception for existing
  integrations until retirement. It reuses the same token on reconnect, so a
  single-use key fails on its second connect. Always use `tokenProvider` for new
  integrations; it wins if both fields are supplied.

## Troubleshooting

- **401 at connect:** the key may be used, expired, revoked, bound to another
  device, or rejected by origin restrictions. Request a fresh key; verify the
  target and any `allowedOrigins` on the server. Do not infer validity from
  `expiresAt` alone or retry the same key.
- **422 on mint:** read the response's `issues` and correct the indicated request
  fields before retrying. Do not retry an unchanged invalid request.
- **Provider failures:** check your app-to-backend authentication and whether the
  backend returns a nonblank key within 10 seconds. Keep synchronous blocking
  work off the UI isolate. Distinguish `credentials_unavailable` from target
  discovery failures in the outer `credentials` callback.
