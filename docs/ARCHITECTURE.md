# Architecture

Player input → Roblox services → CadClient → RelayTransport → receiver → CAD reader → your adapter

The game server owns caller identity, duty membership, location, text filtering, and event IDs. Calls/panics use PUT at stable IDs so a transport retry does not create duplicate receiver records. Unit updates and batched heartbeats use PATCH. Temporary failures wait in a bounded Outbox.

HTTP routes are scoped by a configurable session key and game.JobId. Studio uses a generated ID when JobId is empty. A session can identify a deployment, community, test environment, or gameplay session; it has no built-in dependency on another product's IDs.

The Node receiver is a runnable reference backend. It checks role tokens, validates incoming records, resolves timestamp markers, and commits next-state JSON through a temporary-file rename. One process owns the state file. A production backend can replace that implementation while preserving the contract.

examples/relay-client.cjs demonstrates a backend read with a read-only token. examples/map-to-cad.cjs demonstrates field translation without network/database side effects. examples/read-snapshot.cjs connects them or reads the fictional fixture offline. Your application owns scheduling, account authorization, UI, upserts, and historical storage.

There is no CAD-to-game command channel. Diff/Poller utilities remain from the original core and have tests, but no poller runs in the current game bootstrap.
