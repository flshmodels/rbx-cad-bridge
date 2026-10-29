'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const path = require('node:path');
const { mapToCad } = require('../examples/map-to-cad.cjs');
const fixture = require('../examples/snapshot.json');

test('maps each supported event type without changing the source snapshot', () => {
  const before = structuredClone(fixture);
  const mapped = mapToCad(fixture);
  assert.equal(mapped.calls[0].summary, fixture.servers['demo-server'].calls['call-001'].nature);
  assert.equal(mapped.calls[0].externalId, 'demo-session/demo-server/call-001');
  assert.equal(mapped.units[0].robloxUserId, 42);
  assert.equal(mapped.panics[0].location, 'Main Street [120, -48]');
  assert.deepEqual(fixture, before);
});

test('identical event IDs in different game servers get distinct CAD identifiers', () => {
  const snapshot = structuredClone(fixture);
  snapshot.servers['second-server'] = structuredClone(snapshot.servers['demo-server']);
  const mapped = mapToCad(snapshot);
  assert.equal(new Set(mapped.calls.map(call => call.externalId)).size, 2);
  assert.equal(new Set(mapped.units.map(unit => unit.externalId)).size, 2);
});

test('optional callsigns and empty collections are handled', () => {
  const snapshot = structuredClone(fixture);
  delete snapshot.servers['demo-server'].units[42].callsign;
  assert.equal(mapToCad(snapshot).units[0].callsign, null);
  assert.deepEqual(mapToCad({ session: 'empty', updatedAt: 1, servers: {} }), {
    session: 'empty', updatedAt: 1, calls: [], units: [], panics: []
  });
});

test('malformed snapshots fail instead of silently fabricating CAD data', () => {
  assert.throws(() => mapToCad(null), /snapshot/);
  assert.throws(() => mapToCad({ session: 'x', updatedAt: 1, servers: [] }), /servers/);
  const snapshot = structuredClone(fixture);
  snapshot.servers['demo-server'].calls['call-001'].callerUserId = 'not-a-number';
  assert.throws(() => mapToCad(snapshot), /callerUserId/);
});

test('offline example produces mapped JSON with no network configuration', () => {
  const root = path.resolve(__dirname, '..');
  const result = spawnSync(process.execPath, ['examples/read-snapshot.cjs', '--file', 'examples/snapshot.json'], { cwd: root, encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(JSON.parse(result.stdout).calls[0].summary, 'Vehicle collision');
});
