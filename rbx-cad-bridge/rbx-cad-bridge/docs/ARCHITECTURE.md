# Architecture

## Layers

```
init.server.luau        wiring only: builds objects, injects dependencies, starts loops
      │
Services/               Roblox-facing. Touch Players, TextService, CollectionService, Remotes
      │                 CallService · PanicService · UnitService · DispatchService
      │                 LocationResolver · Notifier
      ▼
Core/CadClient          the CAD's API: calls, units, panics. Owns paths + schema mapping
      │
      ├── Core/Outbox   bounded, expiring queue for transient failures
      ▼
Core/Firebase           REST transport: URL building, auth, retry/backoff, rate limiting, redaction
      │
      ├── Core/RateLimiter / Core/Backoff
      ▼
HttpService  (or Core/DryRunHttp)
```

`Core/Poller` + `Core/Diff` sit beside `CadClient` and turn periodic reads into change events for
the services.

## Why the core has no `require`s

`Core/*` modules take everything they need as constructor arguments: the HTTP object, the clock, the
sleep function, the random source, the limiter. Only `init.server.luau` and `Services/*` know about
Roblox. The payoffs:

1. The core runs under Lune in CI with a scripted fake `HttpService`, so retry, backoff, rate limiting
   and queueing are tested deterministically, with no real network and no real waiting.
2. Swapping behaviour is one line at the wiring site (`DryRunHttp` replaces `HttpService`).
3. The types document the seams: `Firebase` needs a `Limiter`, not a `RateLimiter`.

## Request lifecycle: `/911`

1. Client parses text (`CommandParser`), fires `RequestCall`.
2. `CallService`: table check, per-player token, `Mappers.buildCall` (validate + sanitise), Roblox text
   filter, `Mappers.makeId`.
3. `CadClient.createCall` remaps fields and calls `Firebase.request("PUT", "calls/<id>")`.
4. `Firebase`: validate path, wait for a global token, send. On 408/429/5xx or a thrown network error:
   back off and retry (up to `maxRetries`).
5. If still failing transiently, `CadClient` hands the write to the `Outbox`; the player is told it is
   queued. A background loop flushes the outbox every `flushInterval` seconds, in order.
6. On a permanent error (e.g. 401), the player is told to contact an admin and the details go to the
   server log (never to the player).

## Request lifecycle: dispatcher assigns an officer

1. The CAD writes `assigned` on a call in the database.
2. The `calls` poller (every `pollInterval` seconds) fetches the collection, maps fields back to canonical
   names, and diffs against the previous snapshot.
3. `DispatchService` sees the changed call, checks `Mappers.isAssignedTo` for each player, and notifies
   a player who was not previously assigned.

## Failure behaviour

| Failure | Result |
|---|---|
| Firebase unreachable | Writes retry, then queue; polls back off up to `maxPollInterval`; players are told calls are queued. |
| Token wrong or expired | Permanent (401): not retried, not queued; players get a generic error; the real error is logged. |
| Rate limit exhausted | Requests wait for a token instead of being dropped. |
| Change handler throws | Caught and logged; the poller keeps running. |
| Server shutting down | `BindToClose` stops pollers, marks units offline in a single request, and makes one last outbox flush. |
