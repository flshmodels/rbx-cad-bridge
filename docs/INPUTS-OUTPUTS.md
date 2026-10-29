# Inputs and outputs

## Player-facing inputs

| Input | Accepted values | Output |
| --- | --- | --- |
| /911 incident | 3–80 characters | A pending call using medium priority |
| /911 !priority incident | details | Priority low/medium/high/emergency; details up to 300 characters | A filtered call in the CAD feed |
| /panic | No arguments; player must be on a configured duty team | Panic record, unit panic status, existing in-game alerts |
| Team membership | Exact names in dutyTeams | Unit available/offline events |
| CadCallsign attribute | Optional server-set string, up to 50 characters | Unit and panic display label |
| CadZone tags and ZoneName attributes | Tagged BaseParts and optional zone label | A readable location for calls and panics |

Remote RequestCall receives {nature, description?, priority?}; Panic takes no input. The server obtains identity and location itself. Notify sends a notification kind and message to the player's existing toast UI. Success means accepted by the relay, queued means temporary failure awaiting retry, and rejection means invalid input or a permanent delivery error. It does not confirm a person read the event.

## HTTP inputs

Base for game writes: /v1/sessions/{session}/servers/{server}

| Method and path | Role | Body | Output |
| --- | --- | --- | --- |
| PUT .../calls/{eventId} | game | Call record from SCHEMA.md | 200 {ok:true}; duplicate event is unchanged |
| PUT .../panics/{eventId} | game | Panic record | 200 {ok:true}; duplicate event is unchanged |
| PATCH .../units/{userId} | game | Full initial unit record, or allowed partial fields | 200 {ok:true} |
| PATCH .../units | game | {"42/lastSeen":{"$timestamp":true}} or offline status paths | 200 {ok:true}; batch validates before committing |
| GET /v1/sessions/{session}/snapshot | cad | None | {session, servers:{serverId:{calls,units,panics}}, updatedAt} |
| GET /health | public | None | {ok:true,version:"0.2.0"}; no operational records |

Every non-health route requires Authorization: Bearer TOKEN. Write requests require Content-Type: application/json. IDs use letters, digits, underscore or hyphen, up to 100 characters; reserved object-property names are rejected. Unit IDs must be positive decimal Roblox user IDs. Unknown fields and operations are rejected. The bundled paths/fieldMap must use canonical names.

## Error outputs

Errors use {error:"message"}. Status codes: 400 invalid input, 401 missing/wrong credential, 403 read-only CAD or forbidden operation, 404 unknown route, 405 unsupported method, 413 body over 64 KiB, 415 wrong content type, 429 rate limit, 500 storage/internal error, 507 collection/server capacity. The game retries network failures, 408/429 and 5xx responses with backoff, then queues retryable writes. Permanent failures are reported without repeated requests. Capacity rejections are retryable but may outlast the five-minute outbox retention.

## Configuration inputs

| Setting | Default | Meaning |
| --- | --- | --- |
| Config.relayUrl | https://relay.example.com | Public HTTPS origin, no path or explicit port |
| Config.sessionId | Session 1 channel ID | Routing session; must match CAD config and relay |
| Config.dryRun | true | Log instead of making HTTP requests |
| Config.paths | calls / units / panics | Canonical collections; leave unchanged |
| Config.fieldMap | Empty per collection | Reserved adapter mappings; leave empty with this relay |
| Config.dutyTeams | Police, Sheriff | Exact duty team names |
| Config.zoneTag / nearRadius | CadZone / 60 | Location zone tag and nearby-distance threshold in studs |
| Config.requestBudget | burst 20; 300/min | Shared Roblox HTTP token bucket |
| Config.callLimit | burst 2; refill 30 seconds | Per-player 911 limit |
| Config.panicLimit | burst 1; refill 20 seconds | Per-player panic limit |
| Config.heartbeatInterval | 60 seconds | One batched on-duty unit refresh |
| Config.flushInterval | 10 seconds | Retry queue flush cadence |
| Config.outbox | 50 writes; 300 seconds | Queue capacity and maximum age |
| Secrets.authToken | Placeholder | Session gameToken, server-only |
| CAD_BRIDGE_SESSIONS | Required JSON | Session ID -> {gameToken,cadToken}; unique tokens >=32 chars |
| HOST / PORT | 127.0.0.1 / 8787 | Relay listening interface/port |
| CAD_BRIDGE_STATE | data/state.json | Persistent relay state path |
| cad-bridge.local.json relayUrl | Required | Relay origin; HTTPS, or HTTP loopback for local tests |
| cad-bridge.local.json sessions | Required | Session ID -> read-only CAD token |
| CAD_BRIDGE_TEST_TMP | System temp directory | Optional test scratch-directory override |

## Electron and internal return shapes

cad-bridge:context is renderer-to-main metadata {session,authenticated}; it carries no token. cad-bridge:snapshot takes no payload and returns the selected session's snapshot, or rejects if the caller, session/access context, configuration, or relay response is invalid. The feed shows connection state, event text, unit status, and timestamps. It clears stale data on failure/session changes.

RelayTransport.request returns {ok,status,data?,err?,retryable,attempts}. CadClient writes return {ok,queued,err?}. Outbox.flush returns (sent,remaining). These delivery results are internal code contracts, not dispatcher acknowledgements. Schema field definitions are in SCHEMA.md.
