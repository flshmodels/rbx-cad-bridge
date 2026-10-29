# Adapt the bridge to your CAD

The reusable contract is Roblox events plus a read-only snapshot, not a particular CAD screen. Choose one of two approaches:

1. Keep the example receiver. Your CAD backend reads its snapshot and maps/imports the records.
2. Implement the documented HTTP endpoints in your existing backend. Keep the validation, auth, idempotency, session isolation, and timestamps; replace the file store with your database.

Do not point RelayTransport at an unrelated CAD API and assume it works. The method, URL, body, authentication, response, and retry semantics must agree at both ends.

## Three integration seams

| Seam | File | Typical customization |
| --- | --- | --- |
| Game rules | src/server/Config.luau and Services/ | Teams, zones, caller/unit fields, which events exist |
| Receiver | relay/server.cjs | Storage, authenticated service identity, retention, route contract |
| CAD adapter | examples/map-to-cad.cjs | Rename fields, map priorities/statuses, upsert into your CAD |

Keep Config.paths and fieldMap canonical when using the bundled receiver. They are not a way to transform this receiver into an arbitrary vendor API. For a different wire protocol, implement a transport with the same request result shape and pass it to CadClient in init.server.luau.

## Example adapter inputs and outputs

mapToCad(snapshot) is a pure function. Input is {session,updatedAt,servers:{serverId:{calls,units,panics}}}; each collection is an ID-keyed object described in SCHEMA.md. Output:

| Collection | Output fields |
| --- | --- |
| calls | externalId, serverId, summary, details, priority, location, caller:{userId,name}, createdAt |
| units | externalId, serverId, robloxUserId, name, callsign (string or null), status, lastSeen |
| panics | externalId, serverId, robloxUserId, name, callsign (string or null), location, createdAt |

The root also retains session and updatedAt. Timestamps are Unix milliseconds. The mapper throws TypeError on missing/wrong structural field types instead of guessing values. The relay validates the wire schema; the mapper's checks are not a substitute for receiver validation.

For example, input nature: "Vehicle collision" becomes summary: "Vehicle collision". Your CAD might instead expect incidentType or title: change that mapping and its tests. Convert priority/status values explicitly if your system uses numbers or codes.

Use externalId as the upsert key. It combines session, server ID, and record ID with URI-encoded segments, so two servers cannot overwrite one another's identically named events. Do not insert a new database row on every snapshot poll.

Snapshots can be empty. The reference receiver expires records: your CAD must decide whether disappearance removes an item from its live view or leaves an archived history record. Do not treat an empty snapshot as an instruction to erase historical records. After a failed read, show a disconnected/stale state; do not present an invented empty successful result.

## Framework placement

- Web CAD: run the reader in your authenticated backend and send only authorized records to the browser. Never bundle the read token in public JavaScript.
- Electron CAD: run it in the main process or a backend service; use a narrow IPC interface for the renderer and validate its sender.
- Another language: implement the documented GET snapshot request and equivalent mapping in that language. JavaScript is an example, not a protocol requirement.

The demo prints JSON only. It does not create incidents in any real CAD. A working integration needs your system's authorization checks, upsert code, UI wiring, and acceptance tests.
