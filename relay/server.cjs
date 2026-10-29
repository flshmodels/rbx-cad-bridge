'use strict';

const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const { timingSafeEqual } = require('node:crypto');

const STATUSES = new Set(['offline', 'available', 'busy', 'en_route', 'on_scene', 'panic']);
const COLLECTIONS = new Set(['calls', 'units', 'panics']);
const idOK = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,100}$/.test(value) && !['__proto__', 'constructor', 'prototype'].includes(value);
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const fault = (status, message) => Object.assign(new Error(message), { status });

function prune(state, now) {
  for (const [key, server] of Object.entries(state)) {
    for (const [collection, records] of Object.entries(server)) {
      const age = collection === 'panics' ? 300000 : 86400000;
      for (const [id, record] of Object.entries(records)) {
        if (now - (record.lastSeen ?? record.createdAt) > age) delete records[id];
      }
    }
    if (Object.values(server).every(records => !Object.keys(records).length)) delete state[key];
  }
}

function credentialsValid(credentials) {
  if (!object(credentials) || !Object.keys(credentials).length) throw Error('Configure at least one session');
  const tokens = new Set();
  for (const [session, pair] of Object.entries(credentials)) {
    if (!idOK(session) || !object(pair)) throw Error('Invalid session configuration');
    for (const name of ['gameToken', 'cadToken']) {
      const token = pair[name];
      if (typeof token !== 'string' || token.length < 32 || /[\s\x00-\x1f]/.test(token) || tokens.has(token)) {
        throw Error('Use unique tokens of at least 32 characters for every role and session');
      }
      tokens.add(token);
    }
  }
}

function equal(a, b) {
  const left = Buffer.from(a), right = Buffer.from(b);
  return left.length === right.length && timingSafeEqual(left, right);
}

function clean(value, now, depth = 0) {
  if (depth > 8) throw fault(400, 'Object is too deeply nested');
  if (object(value) && value.$timestamp === true && Object.keys(value).length === 1) return now;
  if (typeof value === 'string' && value.length > 2000) throw fault(400, 'Text is too long');
  if (Array.isArray(value)) throw fault(400, 'Use objects, not arrays');
  if (object(value)) {
    const result = {};
    for (const [key, child] of Object.entries(value)) {
      if (['__proto__', 'prototype', 'constructor'].includes(key)) throw fault(400, 'Invalid field');
      result[key] = clean(child, now, depth + 1);
    }
    return result;
  }
  if (!['string', 'number', 'boolean'].includes(typeof value) && value !== null) throw fault(400, 'Invalid value');
  return value;
}

function fieldsOnly(record, fields) {
  if (!object(record) || Object.keys(record).some(key => !fields.includes(key))) throw fault(400, 'Unsupported fields');
}

function text(record, field, max, required = true) {
  const value = record[field];
  if (value === undefined && !required) return;
  if (typeof value !== 'string' || [...value].length > max || (required && !value.trim())) throw fault(400, `Invalid ${field}`);
}

function validateGame(collection, record, creating) {
  const common = ['source', 'createdAt'];
  if (collection === 'calls') {
    fieldsOnly(record, [...common, 'nature', 'description', 'priority', 'location', 'status', 'callerUserId', 'callerName']);
    text(record, 'nature', 80); text(record, 'description', 300, false); text(record, 'location', 500); text(record, 'callerName', 50);
    if (!Number.isSafeInteger(record.callerUserId) || record.callerUserId <= 0 || record.status !== 'pending' || !['low', 'medium', 'high', 'emergency'].includes(record.priority)) throw fault(400, 'Invalid call');
  } else if (collection === 'panics') {
    fieldsOnly(record, [...common, 'userId', 'username', 'callsign', 'location', 'status']);
    text(record, 'username', 50); text(record, 'location', 500); text(record, 'callsign', 50, false);
    if (!Number.isSafeInteger(record.userId) || record.userId <= 0 || record.status !== 'active') throw fault(400, 'Invalid panic');
  } else {
    fieldsOnly(record, ['source', 'userId', 'username', 'callsign', 'status', 'lastSeen']);
    if (record.status !== undefined && !STATUSES.has(record.status)) throw fault(400, 'Invalid unit status');
    if (creating) {
      text(record, 'username', 50);
      if (!Number.isSafeInteger(record.userId) || record.userId <= 0) throw fault(400, 'Invalid unit');
    }
    text(record, 'callsign', 50, false);
  }
}

function mutate(state, route, method, raw, now) {
  const { session, server, collection, id } = route;
  const key = `${session}/${server}`;
  const existing = state[key];
  if (!existing && Object.keys(state).length >= 64) throw fault(507, 'Server capacity reached');
  const store = existing || { calls: {}, units: {}, panics: {} };
  const records = store[collection];
  const body = clean(raw, now);
  if (!object(body)) throw fault(400, 'Expected a JSON object');
  {
    if (collection === 'units' && method === 'PATCH') {
      if (id) {
        if (!/^[1-9][0-9]*$/.test(id)) throw fault(400, 'Invalid user ID');
        validateGame(collection, body, !records[id]);
        if (body.userId !== undefined && String(body.userId) !== id) throw fault(400, 'User ID mismatch');
        if (!records[id] && Object.keys(records).length >= 500) throw fault(507, 'Unit capacity reached');
        records[id] = { ...records[id], ...body, lastSeen: now, source: 'roblox' };
      } else {
        const entries = Object.entries(body);
        // Validate the whole batch before changing anything.
        for (const [field, value] of entries) {
          const match = /^([1-9][0-9]*)\/(lastSeen|status)$/.exec(field);
          if (!match || !records[match[1]] || (match[2] === 'status' && value !== 'offline')) throw fault(400, 'Invalid unit batch');
        }
        for (const [field, value] of entries) {
          const [userId, name] = field.split('/');
          records[userId][name] = name === 'lastSeen' ? now : value;
        }
      }
    } else if (id && ['calls', 'panics'].includes(collection) && method === 'PUT') {
      validateGame(collection, body, true);
      // Replaying the same game event does not create a second record or change its time.
      if (!records[id]) {
        const max = collection === 'calls' ? 500 : 100;
        if (Object.keys(records).length >= max) throw fault(507, 'Record capacity reached; archive closed records');
        records[id] = { ...body, createdAt: now, source: 'roblox' };
      }
    } else throw fault(403, 'Game role cannot perform this operation');
  }
  state[key] = store;
}

async function readBody(req) {
  if (req.headers['content-type']?.split(';')[0] !== 'application/json') throw fault(415, 'Use application/json');
  let size = 0; const chunks = [];
  for await (const chunk of req) {
    size += chunk.length;
    if (size > 65536) throw fault(413, 'Request is too large');
    chunks.push(chunk);
  }
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); }
  catch { throw fault(400, 'Invalid JSON'); }
}

function createRelay({ credentials, stateFile = null, clock = Date.now, onError = error => console.error('[relay]', error.code || 'internal failure') }) {
  credentialsValid(credentials);
  let state = {};
  if (stateFile && fs.existsSync(stateFile)) {
    state = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
    if (!object(state)) throw Error('Invalid relay state');
  }
  const budgets = new Map();
  const save = next => {
    if (stateFile) {
      fs.mkdirSync(path.dirname(stateFile), { recursive: true });
      fs.writeFileSync(stateFile + '.tmp', JSON.stringify(next), { mode: 0o600 });
      fs.renameSync(stateFile + '.tmp', stateFile);
    }
    state = next;
  };
  const server = http.createServer(async (req, res) => {
    const send = (status, data) => {
      res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
      res.end(JSON.stringify(data));
    };
    try {
      const url = new URL(req.url, 'http://relay');
      if (req.method === 'GET' && url.pathname === '/health') return send(200, { ok: true, version: '0.2.0' });
      const parts = url.pathname.split('/').slice(1);
      if (parts[0] !== 'v1' || parts[1] !== 'sessions' || !idOK(parts[2])) throw fault(404, 'Not found');
      const session = parts[2];
      const pair = Object.hasOwn(credentials, session) ? credentials[session] : null;
      const token = (req.headers.authorization || '').replace(/^Bearer /, '');
      const role = pair && (equal(token, pair.gameToken) ? 'game' : equal(token, pair.cadToken) ? 'cad' : null);
      if (!role) throw fault(401, 'Unauthorized');
      const now = clock(), bucketKey = `${session}/${role}`;
      let budget = budgets.get(bucketKey);
      if (!budget || now - budget.start >= 60000) budgets.set(bucketKey, budget = { start: now, count: 0 });
      if (++budget.count > 1000) { res.setHeader('Retry-After', '60'); throw fault(429, 'Rate limit exceeded'); }
      if (parts.length === 4 && parts[3] === 'snapshot' && role === 'cad' && req.method === 'GET') {
        const servers = {};
        const visible = structuredClone(state);
        prune(visible, now);
        for (const [key, value] of Object.entries(visible)) {
          if (!key.startsWith(session + '/')) continue;
          const snapshot = structuredClone(value);
          for (const unit of Object.values(snapshot.units)) {
            if (now - unit.lastSeen > 150000) unit.status = 'offline';
          }
          servers[key.slice(session.length + 1)] = snapshot;
        }
        return send(200, { session, servers, updatedAt: now });
      }
      if (role === 'cad') throw fault(403, 'The CAD token is read only');
      const [, , , serversSegment, serverId, collection, id] = parts;
      if (serversSegment !== 'servers' || !idOK(serverId) || !COLLECTIONS.has(collection) || (id !== undefined && !idOK(id)) || ![6, 7].includes(parts.length)) throw fault(404, 'Not found');
      const route = { session, server: serverId, collection, id };
      if (!['PUT', 'PATCH'].includes(req.method)) throw fault(405, 'Method not allowed');
      const body = await readBody(req);
      // Clone after the body arrives, so concurrent requests cannot commit stale state.
      const next = structuredClone(state);
      prune(next, now);
      mutate(next, route, req.method, body, now);
      save(next);
      send(200, { ok: true });
    } catch (error) {
      if (!error.status) onError(error);
      if (!res.headersSent && !res.destroyed) send(error.status || 500, { error: error.status ? error.message : 'Relay could not complete the request' });
    }
  });
  server.requestTimeout = 10000;
  server.headersTimeout = 10000;
  return server;
}

if (require.main === module) {
  const credentials = JSON.parse(process.env.CAD_BRIDGE_SESSIONS || '{}');
  const server = createRelay({ credentials, stateFile: process.env.CAD_BRIDGE_STATE || path.resolve('data/state.json') });
  server.listen(Number(process.env.PORT || 8787), process.env.HOST || '127.0.0.1', () => console.log('[relay] listening; put a trusted HTTPS proxy in front for live Roblox use'));
}

module.exports = { createRelay };
