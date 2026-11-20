// Unauthenticated local development helper. Never expose it through a tunnel.
// Production backends must authenticate callers and authorize the requested device.
import { createServer } from 'node:http';
import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { MobilerunSDK } from '@mobilerun/sdk';

export function createHelper(sdk) {
  return createServer(async (req, res) => {
    const reply = (status, body) => {
      res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
      res.end(JSON.stringify(body));
    };
    const port = req.socket.localPort;
    const loopbackHost = [`127.0.0.1:${port}`, `localhost:${port}`, `[::1]:${port}`]
      .includes(req.headers.host);
    const browserRequest = 'origin' in req.headers || 'sec-fetch-site' in req.headers;
    if (!loopbackHost || browserRequest) return reply(403, { error: 'forbidden' });
    const route = /^\/api\/v1\/devices\/([A-Za-z0-9_-]+)(\/stream-key)?$/.exec(req.url ?? '');
    if (!route) return reply(404, { error: 'not_found' });
    const [, deviceId, mint] = route;
    const allowedMethod = mint ? 'POST' : 'GET';
    if (req.method !== allowedMethod) return reply(405, { error: 'method_not_allowed' });
    try {
      if (mint) {
        const result = await sdk.api.post('/identity/stream-keys', {
          body: { deviceId, ttlSeconds: 120 },
          maxRetries: 0,
        });
        return reply(201, { key: result.key, keyId: result.keyId, expiresAt: result.expiresAt });
      }
      const device = await sdk.devices.get(deviceId);
      return reply(200, {
        id: device.info?.id ?? null,
        state: device.info?.state ?? null,
        streamUrl: device.info?.streamUrl ?? null,
      });
    } catch (error) {
      const upstreamRefusal = Number.isInteger(error?.status) && error.status >= 400 && error.status < 600;
      return reply(upstreamRefusal ? error.status : 502, { error: 'upstream_request_failed' });
    }
  });
}

function isEntryPoint() {
  const entry = process.argv[1];
  if (!entry) return false;
  let resolved;
  try {
    resolved = realpathSync(entry);
  } catch {
    try {
      resolved = realpathSync(`${entry}.mjs`);
    } catch {
      return false;
    }
  }
  return resolved === realpathSync(fileURLToPath(import.meta.url));
}

if (isEntryPoint()) {
  if (!process.env.MOBILERUN_API_KEY) throw new Error('Set MOBILERUN_API_KEY in the helper environment');
  const upstream = (process.env.MOBILERUN_API_URL ?? 'https://api.mobilerun.ai/v1').replace(/\/+$/, '');
  const baseURL = upstream.endsWith('/v1') ? upstream : `${upstream}/v1`;
  const sdk = new MobilerunSDK({ apiKey: process.env.MOBILERUN_API_KEY, baseURL, logLevel: 'off' });
  createHelper(sdk).listen(3001, '127.0.0.1');
}
