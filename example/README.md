# Interactive sample

Follow [TESTING.md](../TESTING.md) for setup, launch and the feature checklist.
The existing `lib/main.dart` combines streaming, stats, themes and local approvals.

## Local backend helper

This unauthenticated helper is **local development only**. It binds `127.0.0.1:3001`.
Never expose it through a tunnel. Production integrations must authenticate callers and
authorize the requested device in their own backend.

Provide `MOBILERUN_API_KEY` securely in the helper process environment; never put it in
an app, launch JSON, command-line argument or committed file. The optional helper-process
`MOBILERUN_API_URL` selects the API base (default `https://api.mobilerun.ai/v1`).
It is normalized to end in `/v1`; callers cannot select the upstream via HTTP requests.
Use a supported Node LTS (22+):

```sh
cd example/backend
npm ci
npm start
```

The pinned official `@mobilerun/sdk@6.2.1` serves just two routes:

- `GET /api/v1/devices/:deviceId`: `{id,state,streamUrl}`, absent values null.
- `POST /api/v1/devices/:deviceId/stream-key`: `{key,keyId,expiresAt}`, 201/no-store.
  Calls `sdk.api.post('/identity/stream-keys', {body:{deviceId,ttlSeconds:120},maxRetries:0})`.

Errors have generic bodies and no-store; safe upstream refusal statuses are preserved.
There is no automatic mint retry, credential logging or permissive CORS.

Save a credential-free file outside the checkout:

```json
{"helperBaseUrl":"http://localhost:3001","deviceId":"DEVICE_UUID"}
```

Run `tool/run-sample.sh /path/to/sample.json` from the repository root, or append `--ios`
for Simulator. Android reverses the helper port only on its owned emulator and removes the
mapping during cleanup. iOS Simulator uses localhost. The consumed file is deleted once.
The helper route and `{key,keyId,expiresAt}` DTO retain their transitional wire names.
Each session captures the helper/device binding; metadata discovery supplies a target whose
`tokenProvider` POSTs once per socket. No minted stream token enters form fields, state or storage.

The sample shows `onError` reasons in its status line. The existing manual static form/file
is the deprecated **device token (legacy)** path: a reconnect reuses the pasted token, so a single-use stream token
fails on the second connect (use the provider), and the session logs a deprecation warning. `e2e_main.dart` and `benchmark_main.dart` retain their static
launch formats. Pending provider Futures have a 10-second deadline and cannot delay
teardown; callbacks must not block the Dart isolate (offload blocking/CPU work themselves).
The socket watchdog starts after minting. Close 1001 immediately tears down media in every
mode and reconnects with a fresh provider stream token (static mode reuses its token); other closes
keep this SDK's existing rebuild behaviour.

Test the helper with `npm test` in `backend`; test the sample with `flutter test` here.
