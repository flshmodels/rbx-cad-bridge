'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { once } = require('node:events');
const { createRelay } = require('../relay/server.cjs');
const { createClient, validateConfig } = require('../examples/relay-client.cjs');
const credentials = {
  session1: { gameToken: 'game1_'.repeat(8), cadToken: 'cad1_'.repeat(8) },
  session2: { gameToken: 'game2_'.repeat(8), cadToken: 'cad2_'.repeat(8) }
};
const call = { nature: 'Vehicle collision', description: 'Two cars', location: 'Main Street', callerUserId: 12, callerName: 'Caller', priority: 'high', status: 'pending', source: 'roblox', createdAt: { $timestamp: true } };
const unit = { userId: 42, username: 'Trooper', callsign: '1A-12', status: 'available', lastSeen: { $timestamp: true }, source: 'roblox' };
function temp(t) {
  const dir = fs.mkdtempSync(path.join(process.env.CAD_BRIDGE_TEST_TMP || os.tmpdir(), 'cad-bridge-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  return dir;
}
async function fixture(t, options = {}) {
  let now = 1800000000000;
  const server = createRelay({ credentials, clock: () => now, ...options });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }));
  const origin = `http://127.0.0.1:${server.address().port}`;
  async function request(route, method = 'GET', body, token = credentials.session1.gameToken) {
    const response = await fetch(origin + route, { method, headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body) });
    return { status: response.status, data: await response.json() };
  }
  const snapshot = async (session = 'session1') => (await request(`/v1/sessions/${session}/snapshot`, 'GET', undefined, credentials[session].cadToken)).data;
  const base = '/v1/sessions/session1/servers/job1/';
  return { origin, request, snapshot, base, advance: ms => { now += ms; } };
}

test('game call/unit writes are readable through an independent CAD reader', async t => {
  const { origin, request, base } = await fixture(t);
  assert.equal((await request(base + 'calls/c1', 'PUT', call)).status, 200);
  assert.equal((await request(base + 'units/42', 'PATCH', unit)).status, 200);
  const cad = createClient({ relayUrl: origin, sessions: { session1: credentials.session1.cadToken } });
  const data = await cad('session1', 'snapshot');
  assert.equal(data.servers.job1.calls.c1.nature, call.nature);
  assert.equal(typeof data.servers.job1.calls.c1.createdAt, 'number');
  assert.equal(data.servers.job1.units[42].username, 'Trooper');
  await assert.rejects(cad('session1', 'servers/job1/calls/c1'), /only reads/);
});

test('game event replay is idempotent and keeps the first creation timestamp', async t => {
  const { request, snapshot, base, advance } = await fixture(t);
  await request(base + 'calls/c1', 'PUT', call);
  const original = (await snapshot()).servers.job1.calls.c1;
  advance(1000);
  await request(base + 'calls/c1', 'PUT', call);
  const data = (await snapshot()).servers.job1.calls;
  assert.equal(Object.keys(data).length, 1);
  assert.deepEqual(data.c1, original);
});

test('session and server boundaries prevent mixing game data', async t => {
  const { request, snapshot, base } = await fixture(t);
  await request(base + 'calls/c1', 'PUT', call);
  await request(base.replace('job1', 'job2') + 'calls/c1', 'PUT', { ...call, nature: 'Different game server' });
  const data = await snapshot();
  assert.equal(data.servers.job1.calls.c1.nature, call.nature);
  assert.equal(data.servers.job2.calls.c1.nature, 'Different game server');
  assert.equal((await request('/v1/sessions/session2/snapshot', 'GET', undefined, credentials.session1.cadToken)).status, 401);
  assert.deepEqual((await snapshot('session2')).servers, {});
});

test('CAD credentials are read only; no command or dispatch routes exist', async t => {
  const { request, base } = await fixture(t);
  await request(base + 'calls/c1', 'PUT', call);
  for (const method of ['PUT', 'PATCH', 'DELETE']) {
    assert.equal((await request(base + 'calls/c1', method, method === 'DELETE' ? undefined : { status: 'closed' }, credentials.session1.cadToken)).status, 403);
  }
  assert.equal((await request('/v1/sessions/session1/snapshot')).status, 404);
  assert.equal((await request(base + 'calls', 'GET', undefined, 'wrong')).status, 401);
  assert.equal((await request(base + 'calls')).status, 405);
});

test('heartbeat batch is atomic and stale units appear offline', async t => {
  const { request, snapshot, base, advance } = await fixture(t);
  await request(base + 'units/42', 'PATCH', unit);
  assert.equal((await request(base + 'units', 'PATCH', { '42/status': 'offline', '999/status': 'offline' })).status, 400);
  assert.equal((await snapshot()).servers.job1.units[42].status, 'available');
  advance(151000);
  assert.equal((await snapshot()).servers.job1.units[42].status, 'offline');
  await request(base + 'units', 'PATCH', { '42/lastSeen': { $timestamp: true } });
  assert.equal((await snapshot()).servers.job1.units[42].status, 'available');
  await request(base + 'units', 'PATCH', { '42/status': 'offline', '42/lastSeen': { $timestamp: true } });
  assert.equal((await snapshot()).servers.job1.units[42].status, 'offline');
});

test('rejects injected fields, prototype keys, invalid IDs, and invalid status', async t => {
  const { request, base } = await fixture(t);
  assert.equal((await request(base + 'calls/c1', 'PUT', { ...call, assigned: { 42: true } })).status, 400);
  assert.equal((await request(base + 'calls/c1', 'PUT', JSON.parse('{"__proto__":{"polluted":true}}'))).status, 400);
  assert.equal((await request(base + 'units/43', 'PATCH', unit)).status, 400);
  assert.equal((await request(base + 'units/42', 'PATCH', { ...unit, status: 'made_up' })).status, 400);
  assert.equal((await request(base + 'calls/a.b', 'PUT', call)).status, 404);
  assert.equal((await request(base + 'calls/__proto__', 'PUT', call)).status, 404);
  assert.equal((await request(base + 'calls/c1', 'POST', call)).status, 405);
  assert.equal({}.polluted, undefined);
});

test('panic records reach the CAD snapshot', async t => {
  const { request, snapshot, base } = await fixture(t);
  const panic = { userId: 42, username: 'Trooper', callsign: '1A-12', location: 'Main Street', status: 'active', source: 'roblox', createdAt: { $timestamp: true } };
  assert.equal((await request(base + 'panics/p1', 'PUT', panic)).status, 200);
  assert.equal((await snapshot()).servers.job1.panics.p1.location, 'Main Street');
});

test('panic alerts expire after five minutes; calls and abandoned units after a day', async t => {
  const { request, snapshot, base, advance } = await fixture(t);
  await request(base + 'calls/c1', 'PUT', call);
  await request(base + 'units/42', 'PATCH', unit);
  await request(base + 'panics/p1', 'PUT', { userId: 42, username: 'Trooper', location: 'Main Street', status: 'active', createdAt: { $timestamp: true }, source: 'roblox' });
  advance(300001);
  assert.deepEqual((await snapshot()).servers.job1.panics, {});
  assert.equal((await snapshot()).servers.job1.calls.c1.nature, call.nature);
  advance(86400000);
  assert.deepEqual((await snapshot()).servers, {});
});

test('disk persistence survives a second relay instance loading the saved file', async t => {
  const stateFile = path.join(temp(t), 'state.json');
  const first = await fixture(t, { stateFile });
  const saved = await first.request(first.base + 'calls/c1', 'PUT', call);
  assert.equal(saved.status, 200, JSON.stringify(saved));
  const second = await fixture(t, { stateFile });
  assert.equal((await second.snapshot()).servers.job1.calls.c1.nature, call.nature);
});

test('failed storage writes do not commit data in memory', async t => {
  const stateFile = path.join(temp(t), 'state.json');
  const { request, snapshot, base } = await fixture(t, { stateFile, onError: () => {} });
  fs.mkdirSync(stateFile + '.tmp');
  assert.equal((await request(base + 'calls/c1', 'PUT', call)).status, 500);
  assert.deepEqual((await snapshot()).servers, {});
});

test('CAD reader refuses public cleartext and credential-bearing URLs', () => {
  assert.throws(() => validateConfig({ relayUrl: 'http://public.example.com', sessions: {} }));
  assert.throws(() => validateConfig({ relayUrl: 'https://user:pass@example.com', sessions: {} }));
  assert.throws(() => validateConfig({ relayUrl: 'https://example.com/path', sessions: {} }));
  assert.equal(validateConfig({ relayUrl: 'https://example.com', sessions: {} }), 'https://example.com');
});

test('requires unique role tokens of at least 32 characters', () => {
  assert.throws(() => createRelay({ credentials: {} }));
  assert.throws(() => createRelay({ credentials: { one: { gameToken: 'short', cadToken: 'short' } } }));
  assert.throws(() => createRelay({ credentials: { one: { gameToken: 'x'.repeat(32), cadToken: 'x'.repeat(32) } } }));
});
