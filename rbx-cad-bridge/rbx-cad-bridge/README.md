# rbx-cad-bridge

A server-authoritative bridge between a Roblox game and a web-based **CAD (computer-aided dispatch)**
system backed by the **Firebase Realtime Database**. Built for police/emergency roleplay games.

Players dial `/911` in game and the call appears on the dispatcher's CAD. Officers go on duty by
joining a team and appear as live units. A panic button alerts every on-duty unit instantly and
writes a panic record the CAD can react to. When a dispatcher assigns an officer to a call in the
CAD, that officer gets a notification in game.

```
 ┌──────────────┐   RemoteEvents    ┌───────────────────────────┐   HTTPS (REST)   ┌──────────────────┐
 │ Roblox client│ ────────────────► │  Roblox server            │ ───────────────► │ Firebase Realtime│
 │ /911  /panic │ ◄──────────────── │  CadBridge (this repo)    │ ◄─────────────── │ Database         │
 │ toasts       │   notifications   │  rate limit · validate ·  │   PUT/PATCH/GET  │   ▲              │
 └──────────────┘                   │  retry · queue · poll     │                  │   │ listeners    │
                                    └───────────────────────────┘                  │ ┌─┴────────────┐ │
                                                                                   │ │ Web CAD (HTML)│ │
                                                                                   └─┴──────────────┴─┘
```

The game server is the only thing that ever talks to the database. Clients cannot read your
database URL or token, cannot choose paths or field names, and cannot send more than the server
allows.

## What it does

| Part | Direction | What happens |
|---|---|---|
| **CallService** | game → CAD | `/911 !high Shots fired \| man with a handgun` becomes a call record with a priority, a dispatcher-friendly location (`Courthouse [120, -48]`) and the caller's identity. |
| **PanicService** | game → CAD | `/panic` (on-duty units only) writes a panic record, sets the unit's status to `panic`, and instantly alerts every other on-duty unit in game. |
| **UnitService** | both | Joining a duty team registers the player as a unit; leaving or disconnecting marks them offline. One batched heartbeat request keeps `lastSeen` fresh for every on-duty unit. Status changes a dispatcher makes in the CAD are pushed back to the player. |
| **DispatchService** | CAD → game | Polls calls; when a dispatcher assigns an officer, that officer gets a toast with the call. |
| **LocationResolver** | game | Tag `Part`s with `CadZone` (attribute `ZoneName`) in Studio to define named zones. |

## Engineering notes (the interesting parts)

The Roblox-independent core lives in `src/server/Core` and has **zero `require`s**: every dependency is
injected. That is what lets the same code run under [Lune](https://github.com/lune-org/lune) in CI,
with a fake `HttpService`, a fake clock and no Roblox at all.

* **Rate limiting (`RateLimiter`)**: a token bucket. Roblox allows roughly 500 `HttpService` requests
  per minute per server, and a CAD bridge is exactly the kind of thing that blows through that. Every
  request spends a token; if none are free the caller waits instead of failing. Players also get a
  per-player limiter (`KeyedLimiter`) so one person cannot spam calls.
* **Retries with backoff (`Backoff`, `Firebase`)**: transient failures (network errors, HTTP 408/429/5xx)
  retry with exponential backoff and equal jitter, honouring `Retry-After`. Permanent failures
  (401/403/400) return immediately instead of hammering the database.
* **Idempotent writes**: the server generates a time-ordered key for each call and uses `PUT`, so a
  retried request overwrites the same record instead of creating a duplicate. `POST` is never retried.
* **Outbox (`Outbox`)**: if the CAD is unreachable, writes wait in a bounded, expiring in-memory queue and
  replay in order. A 911 call during a brief outage is delayed, not lost. Permanent rejections are
  dropped so they cannot block the queue.
* **Polling with diffing (`Poller`, `Diff`)**: `HttpService` cannot hold a streaming connection, so
  the bridge polls and diffs snapshots. The first poll is a silent baseline (so old calls are not
  replayed on every server start), failures back off, and a throwing handler cannot kill the loop.
* **Schema mapping (`Mappers.remap`)**: the bridge uses canonical field names; `Config.fieldMap`
  translates them to whatever your CAD stores, in both directions.
* **Batching**: heartbeats for every on-duty unit are one multi-path `PATCH`, so the cost does not grow
  with player count.
* **Never trust the client**: payload shape, rate limit, field validation, text sanitising, and
  Roblox text filtering all run on the server, in that order. Extra fields a client sends are ignored
  because records are built from validated pieces, not copied from the payload.
* **Secrets hygiene**: the auth token is redacted from every error and log line, and `DryRunHttp`
  logs URLs without their query string.
* **Dry-run mode**: until you configure a real URL, the bridge runs with a stand-in `HttpService` that
  logs requests instead of sending them, so you can try it in Studio with no setup.

## Setup

You need [Rojo](https://rojo.space) 7.4+ (the tools are pinned in `rokit.toml`).

1. **Build the project**
   ```
   rojo build -o CadBridge.rbxl
   ```
   or run `rojo serve` and connect from Studio. It creates `ServerScriptService.CadBridgeServer`,
   `ReplicatedStorage.CadBridgeShared`, a client script in `StarterPlayerScripts`, and turns on
   `HttpService.HttpEnabled`.
2. **Try it with no database.** Press Play. The output shows `DRY RUN` and a `[dry-run]` line for every
   request the bridge would send. In the chat, type `/911 Test call | testing the bridge`.
3. **Connect your database.**
   * Set `databaseUrl` in `src/server/Config.luau`.
   * Copy `src/server/Secrets.example.luau` to `src/server/Secrets.luau` and add your token.
     `Secrets.luau` is gitignored.
   * Set `paths` and `fieldMap` in `Config.luau` to match how your CAD stores calls, units and panics
     (see `docs/SCHEMA.md`).
   * In Game Settings > Security, enable **Allow HTTP Requests** for the published place.
4. **Mark who is a unit.** Put the teams you want in `Config.dutyTeams`. Optionally set a player attribute
   `CadCallsign` (string) from your own code and it will be sent with their unit and panic records.
5. **Define zones (optional).** Add the `CadZone` tag to any `Part` and give it a `ZoneName` attribute.

### Commands

```
/911 [!low|!medium|!high|!emergency] <what's happening> | <details>
/911 Suspicious vehicle | white van, no plates, behind the school
/911 !emergency Officer down
/panic
```

## Testing

```
lune run tests/run
```

Sixty-plus tests cover the rate limiter, backoff, diffing, validation, retry and outbox behaviour,
token redaction, schema mapping, the poller, and the chat parser, all without Roblox. CI also runs
`stylua --check`, `selene`, and a Rojo build.

## Limitations (read these)

* **Roblox-side behaviour needs a real server to verify.** The pure core is unit-tested; the services
  that touch `Players`, `TextService` and `TextChatService` are type-checked against Roblox's API
  definitions and meant to be exercised in Studio (use dry-run mode first).
* **Polling, not push.** Dispatcher actions reach the game within `Config.pollInterval` seconds (default 5).
* **The outbox is in memory.** If a server shuts down with writes queued, they are lost. A persistent
  queue would need DataStore or `MessagingService`; I chose not to add that cost for a first version.
* **Rapid status flips can race.** Two changes sent in quick succession travel as separate requests
  and are not guaranteed to land in order.
* **Roblox chat commands require `TextChatService`** (the default for new places).
* **Auth model.** See `docs/SECURITY.md`. The default (a token in a server-only module) is
  appropriate for a private community game, not for a public template with a shared token.

## Layout

```
src/
  server/
    init.server.luau      bootstrap: wires Core to Roblox, starts services
    Config.luau           every tunable
    Core/                 pure, dependency-injected, unit-tested
    Services/             Roblox-facing services
  shared/                 Remotes names, CommandParser (client + tests)
  client/                 chat commands + notification toasts
tests/                    Lune test suite
docs/                     ARCHITECTURE, SCHEMA, SECURITY
```

## License

MIT
