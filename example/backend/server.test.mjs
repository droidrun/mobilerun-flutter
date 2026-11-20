import assert from 'node:assert/strict';
import { once } from 'node:events';
import { test } from 'node:test';
import { createHelper } from './server.mjs';

async function start(t, sdk) {
  const server = createHelper(sdk).listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise(resolve => server.close(resolve)));
  return `http://127.0.0.1:${server.address().port}`;
}

test('metadata exposes only the device DTO and never credentials', async t => {
  const calls = [];
  const base = await start(t, { devices: { get: async id => {
    calls.push(id);
    return { info: { id, state: 'running', streamUrl: 'wss://stream.test/s', streamToken: 'private' },
      apiKey: 'parent-key' };
  } } });
  const response = await fetch(`${base}/api/v1/devices/device-a`);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.equal(response.headers.get('access-control-allow-origin'), null);
  assert.deepEqual(await response.json(), { id: 'device-a', state: 'running',
    streamUrl: 'wss://stream.test/s' });
  assert.deepEqual(calls, ['device-a']);
});

test('absent metadata values are null', async t => {
  const base = await start(t, { devices: { get: async () => ({}) } });
  assert.deepEqual(await (await fetch(`${base}/api/v1/devices/device-a`)).json(),
    { id: null, state: null, streamUrl: null });
});

test('mint uses the exact official SDK path, body, retry option and DTO', async t => {
  const calls = [];
  const base = await start(t, { api: { post: async (...args) => {
    calls.push(args);
    return { key: 'key-a', keyId: 'id-a', expiresAt: '2026-11-20T12:00:00Z', apiKey: 'parent-key' };
  } } });
  const response = await fetch(`${base}/api/v1/devices/device-a/stream-key`, { method: 'POST' });
  assert.equal(response.status, 201);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.deepEqual(await response.json(), { key: 'key-a', keyId: 'id-a',
    expiresAt: '2026-11-20T12:00:00Z' });
  assert.deepEqual(calls, [['/identity/stream-keys', {
    body: { deviceId: 'device-a', ttlSeconds: 120 }, maxRetries: 0,
  }]]);
});

for (const status of [401, 403, 404, 429, 503, undefined]) {
  test(`upstream refusal ${status} is generic, no-store and never retried`, async t => {
    let calls = 0;
    const base = await start(t, { api: { post: async () => {
      calls++;
      throw Object.assign(new Error('parent-key private-token private-url'), { status });
    } } });
    const response = await fetch(`${base}/api/v1/devices/device-a/stream-key`, { method: 'POST' });
    assert.equal(response.status, status ?? 502);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    assert.deepEqual(await response.json(), { error: 'upstream_request_failed' });
    assert.equal(calls, 1);
  });
}

test('metadata errors and unknown routes remain generic and no-store', async t => {
  const base = await start(t, { devices: { get: async () => { throw new Error('parent-key'); } } });
  const failure = await fetch(`${base}/api/v1/devices/device-a`);
  assert.equal(failure.status, 502);
  assert.equal(failure.headers.get('cache-control'), 'no-store');
  assert.deepEqual(await failure.json(), { error: 'upstream_request_failed' });
  const unknown = await fetch(`${base}/anything`);
  assert.equal(unknown.status, 404);
  assert.equal(unknown.headers.get('cache-control'), 'no-store');
  const wrongMethod = await fetch(`${base}/api/v1/devices/device-a/stream-key`);
  assert.equal(wrongMethod.status, 405);
  assert.equal(wrongMethod.headers.get('cache-control'), 'no-store');
});
