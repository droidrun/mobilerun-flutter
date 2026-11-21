← [README](../README.md) · [Partner guide](https://docs.mobilerun.ai/partners)

# Stream keys

`StreamCredentials.tokenProvider` is bound to its device target and runs once before
**every new signalling socket**, including retries, wake and rejected upgrades. Mint
through your authenticated backend: `POST /v1/identity/stream-keys` with
`{deviceId, ttlSeconds: 120}`. Keep the parent API key on that server. Keys are single-use;
do not store them, infer validity from expiry, or reuse one for reconnect.

The provider has an independent **10-second deadline**. Throws, failed Futures and
blank keys count as one normal attempt failure with bounded backoff and zero sockets.
There is no fallback to a static or embedded URL token. Nonblank strings are passed
verbatim through the existing query encoder. Late results after timeout, close or target
replacement open nothing. Teardown never waits for a pending provider Future.
Callbacks must be non-blocking: offload synchronous blocking/CPU work using `compute`
or `Isolate.run` where the captured data supports it. Dart cannot run its timers while
application code blocks the isolate.

Provider mode accepts `wss` with a valid host, or `ws` only to exact `localhost`,
`127.0.0.1` or IPv6 loopback. Validation happens before minting. The **45-second connect
watchdog** and **15-second WebSocket-open** budget begin at socket allocation. RTC
configuration retains its subsequent **15-second** budget; minting consumes none of them. ICE refresh
on an existing socket never mints. A callback-only target update keeps healthy media;
the next attempt uses the latest callback. Recreate the session for a different device.

## Errors

`DeviceStreamSession(onError: ...)` receives a `StreamError` for every failed
attempt: `reason`, a `message` without URL or key, the consecutive `attempt`
number and `isFinal`, which is true once retries stop (the stream is then
`StreamUnavailable` until `retry()`).

| `reason.code` | Meaning |
| --- | --- |
| `credentials_unavailable` | The provider threw, returned a blank key or missed its 10-second deadline. |
| `token_rejected` | The upgrade returned HTTP 401 or 403: the key was invalid, expired or already used. |
| `connection_refused` | The socket failed or closed before it opened (host, device or origin). |
| `disconnected` | An open session dropped, including the server session cap. |
| `unknown` | Anything else, such as the connect watchdog or a negotiation failure. |

`device_unavailable` exists for parity with the other SDKs; the current protocol
has no offline message, so it is not produced yet. A callback that throws is
ignored. The first connection with a static `token` logs one deprecation warning
per session.

Close **1001** immediately releases peer/channels/media, timers and pending screenshots,
then reconnects with a fresh key. Flutter retains its existing full-rebuild behaviour for
other closes too. The static `token` field/path is deprecated in documentation but remains
source-compatible, including null/empty behaviour. It is a legacy diagnostic option;
a pasted single-use key cannot support reconnect. Target discovery (`credentials`) is
unchanged and is not deprecated.

See [the sample helper](../example/README.md) for a credential-free local launch.
Shared token-provider fixture replay is pending an approved conformance release;
the new provider behaviour is currently covered by local lifecycle tests.
