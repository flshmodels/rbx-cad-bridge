'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter, once } = require('node:events');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { install } = require('../electron/main.cjs');
const { createRelay } = require('../relay/server.cjs');

async function fixture(t) {
  const app = new EventEmitter(), ipc = new EventEmitter();
  const handlers = new Map(); ipc.handle = (name, callback) => handlers.set(name, callback);
  const wc = new EventEmitter(); wc.mainFrame = {};
  const win = { webContents: wc, isDestroyed: () => false };
  const trusted = { sender: wc, senderFrame: wc.mainFrame };
  const token = 'cad_test_'.repeat(8);
  const relay = createRelay({ credentials: { session1: { gameToken: 'game_test_'.repeat(8), cadToken: token } } });
  relay.listen(0, '127.0.0.1'); await once(relay, 'listening');
  t.after(() => new Promise(resolve => { relay.close(resolve); relay.closeAllConnections(); }));
  const dir = fs.mkdtempSync(path.join(process.env.CAD_BRIDGE_TEST_TMP || os.tmpdir(), 'cad-ipc-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const configPath = path.join(dir, 'cad-bridge.local.json');
  fs.writeFileSync(configPath, JSON.stringify({ relayUrl: `http://127.0.0.1:${relay.address().port}`, sessions: { session1: token } }));
  install({ app, ipcMain: ipc, getMainWindow: () => win, configPath });
  return { app, ipc, handlers, wc, trusted, snapshot: () => handlers.get('cad-bridge:snapshot')(trusted) };
}

test('Electron adapter requires CAD login context and trusts only the main frame', async t => {
  const f = await fixture(t);
  await assert.rejects(f.snapshot(), /Log into/);
  f.ipc.emit('cad-bridge:context', { ...f.trusted, senderFrame: {} }, { session: 'session1', authenticated: true });
  await assert.rejects(f.snapshot(), /Log into/);
  f.ipc.emit('cad-bridge:context', f.trusted, { session: 'session1', authenticated: true });
  assert.equal((await f.snapshot()).session, 'session1');
  await assert.rejects(f.handlers.get('cad-bridge:snapshot')({ sender: {}, senderFrame: {} }), /Untrusted/);
  assert.deepEqual([...f.handlers.keys()], ['cad-bridge:snapshot']);
});

test('logout and main-frame navigation revoke access', async t => {
  const f = await fixture(t);
  f.ipc.emit('cad-bridge:context', f.trusted, { session: 'session1', authenticated: true });
  f.app.emit('web-contents-created', {}, f.wc);
  f.wc.emit('did-start-navigation', {}, 'file:///cad', false, true);
  await assert.rejects(f.snapshot(), /Log into/);
  f.ipc.emit('cad-bridge:context', f.trusted, { session: 'session1', authenticated: true });
  f.ipc.emit('cad-bridge:context', f.trusted, { session: '', authenticated: false });
  await assert.rejects(f.snapshot(), /Log into/);
});

test('session changes discard an in-flight response', async t => {
  const f = await fixture(t);
  f.ipc.emit('cad-bridge:context', f.trusted, { session: 'session1', authenticated: true });
  const pending = f.snapshot();
  f.ipc.emit('cad-bridge:context', f.trusted, { session: '', authenticated: false });
  await assert.rejects(pending, /Session changed/);
});
