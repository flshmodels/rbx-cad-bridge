# rbx-cad-bridge

Send Roblox 911 calls, unit updates and panic alerts to a computer-aided dispatch (CAD) backend. The receiver and sample adapter give you a starting point for connecting your own CAD.

Players submit 911 calls, duty teams create unit-presence updates, and on-duty players can trigger a panic alert. The Roblox server validates these events and sends them to an HTTP receiver. An example CAD reader maps the receiver's snapshot into a simple CAD-shaped data model.

```text
Roblox client → Roblox server → HTTPS receiver → your CAD backend → your CAD UI
```

The feed runs one way, from Roblox to your CAD. It is not tied to a particular CAD or desktop framework. You write the final adapter for the system you use.

## Setup

Node 20 or later is enough. There are no npm dependencies to install.

```sh
npm run demo
```

This reads fictional events from examples/snapshot.json, maps them with examples/map-to-cad.cjs, and prints JSON. It makes no network calls and writes nothing to a CAD. Compare [the input format](docs/SCHEMA.md) with [the adapter outputs](docs/ADAPTING.md).

## What's included

| Part | Purpose |
| --- | --- |
| Roblox services | Server-owned identity/location, input validation, text filtering, duty checks |
| RelayTransport | Authenticated HTTP, request budgeting, retries with backoff |
| Outbox | Bounded temporary delivery queue during an outage |
| Node receiver | Session/server separation, role tokens, schema validation, timestamp handling, file-backed storage |
| CAD reader | Backend-only snapshot reads with read-only credentials |
| Example mapper | Translating canonical events into your CAD's field names |
| Tests | Delivery, duplicates, access boundaries, retention, persistence, and mapping |

## Use it in your project

1. Choose a session key such as demo-session. This is your own routing label, not a third-party account/channel ID.
2. Configure and host the receiver behind public HTTPS. See [configuration](docs/INPUTS-OUTPUTS.md). The provided Node receiver is one example; your existing CAD backend can implement the same contract.
3. Configure src/server/Config.luau, create the ignored server-only Secrets.luau, and use your game's actual team names. Start with dryRun enabled.
4. Connect the CAD backend using examples/relay-client.cjs. Adapt examples/map-to-cad.cjs and upsert the mapped records into your CAD or application state.
5. Test call delivery, duty changes, panic alerts, outages, and duplicate handling in a published test game before relying on the feed.

The [adaptation guide](docs/ADAPTING.md) explains how to connect web, Electron and other CAD applications. [Inputs/outputs](docs/INPUTS-OUTPUTS.md) lists the commands, routes, configuration values, and return shapes.

## Start the example receiver

Generate two separate random tokens, at least 32 characters each:

```sh
node -e "console.log(require('node:crypto').randomBytes(32).toString('hex'))"
```

PowerShell example (replace both placeholders):

```powershell
$env:CAD_BRIDGE_SESSIONS = '{"demo-session":{"gameToken":"YOUR_UNIQUE_GAME_TOKEN_AT_LEAST_32_CHARS","cadToken":"YOUR_DIFFERENT_CAD_TOKEN_AT_LEAST_32_CHARS"}}'
npm start
```

The receiver binds to 127.0.0.1:8787. That address is useful for local backend tests; a live Roblox server needs a reachable HTTPS endpoint. Deploying that endpoint is outside this example. The default state file is data/state.json; run one receiver process per file.

To read a live snapshot from a backend/terminal:

```powershell
$env:CAD_RELAY_URL = 'https://relay.example.com'
$env:CAD_SESSION_ID = 'demo-session'
$env:CAD_READ_TOKEN = 'YOUR_DIFFERENT_CAD_TOKEN_AT_LEAST_32_CHARS'
npm run read:snapshot
```

## Roblox setup

With Rojo available, build a test place using rojo build -o CadBridge.rbxl default.project.json, or use rojo serve to sync into an existing game. This is game-side code, not a Studio plugin. Enable Allow HTTP Requests before live use.

```text
/911 [!low|!medium|!high|!emergency] <incident> | <details>
/911 !high Vehicle collision | Two cars blocking an intersection
/panic
```

## Tests and limits

```sh
npm test
lune run tests/run
```

Node checks run with the built-in test runner. Luau checks need Lune; the workflow also includes Roblox lint/build/type checks. See [verification](docs/VERIFICATION.md) for what was actually run.

- No universal CAD connector or production hosting is included. The adapter is the code you customize.
- The example reader runs once. Your backend chooses its refresh interval and how to display or store results.
- The game outbox is memory-only: pending events can be lost on shutdown, expiry, or overflow. Relay acceptance does not confirm CAD ingestion or dispatcher acknowledgement.
- Calls expire after 24 hours; panic records after 5 minutes. Units appear offline after 150 seconds without updates and expire after 24 hours.
- Default capacity limits are 64 server namespaces, 500 calls/units and 100 panics per namespace. The receiver rejects new records when full rather than silently discarding them.
- Credentials use a shared service-token model suitable for a controlled reference setup. Production account authorization and distributed storage need additional design. See [security](docs/SECURITY.md).
- Live Roblox behavior has not been verified in this update.

MIT license. Examples use fictional data. Keep real credentials and private deployment files out of Git.
