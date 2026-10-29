'use strict';

function record(value, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw TypeError(`${label} must be an object`);
  return value;
}
function text(value, label) {
  if (typeof value !== 'string') throw TypeError(`${label} must be a string`);
  return value;
}
function number(value, label) {
  if (!Number.isFinite(value)) throw TypeError(`${label} must be a number`);
  return value;
}

// This is the integration seam. Replace the field names below with your CAD's schema.
// The function is pure: it does not call an API, modify a database, or send commands.
function mapToCad(snapshot) {
  record(snapshot, 'snapshot');
  const session = text(snapshot.session, 'session');
  const output = { session, updatedAt: number(snapshot.updatedAt, 'updatedAt'), calls: [], units: [], panics: [] };
  for (const [serverId, server] of Object.entries(record(snapshot.servers, 'servers'))) {
    record(server, 'server');
    // Include session + server in every external ID: user/event IDs alone can collide.
    const externalId = id => [session, serverId, id].map(encodeURIComponent).join('/');
    for (const [id, call] of Object.entries(record(server.calls, 'calls'))) {
      record(call, 'call');
      output.calls.push({
        externalId: externalId(id), serverId,
        summary: text(call.nature, 'nature'), details: text(call.description ?? '', 'description'),
        priority: text(call.priority, 'priority'), location: text(call.location, 'location'),
        caller: { userId: number(call.callerUserId, 'callerUserId'), name: text(call.callerName, 'callerName') },
        createdAt: number(call.createdAt, 'createdAt')
      });
    }
    for (const [id, unit] of Object.entries(record(server.units, 'units'))) {
      record(unit, 'unit');
      output.units.push({
        externalId: externalId(id), serverId,
        robloxUserId: number(unit.userId, 'userId'), name: text(unit.username, 'username'),
        callsign: unit.callsign == null ? null : text(unit.callsign, 'callsign'),
        status: text(unit.status, 'status'), lastSeen: number(unit.lastSeen, 'lastSeen')
      });
    }
    for (const [id, panic] of Object.entries(record(server.panics, 'panics'))) {
      record(panic, 'panic');
      output.panics.push({
        externalId: externalId(id), serverId,
        robloxUserId: number(panic.userId, 'userId'), name: text(panic.username, 'username'),
        callsign: panic.callsign == null ? null : text(panic.callsign, 'callsign'),
        location: text(panic.location, 'location'), createdAt: number(panic.createdAt, 'createdAt')
      });
    }
  }
  return output;
}

module.exports = { mapToCad };
