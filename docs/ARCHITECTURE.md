# Architecture

Player chat/teams → Roblox services → CadClient → RelayTransport → relay → Electron IPC → RobloxFeed

The Roblox server owns the caller identity, unit membership, location, filtering, and event ID. Clients cannot supply a relay route or token. Calls and panics are PUT at stable IDs so transport retries do not create a second event. Unit updates and batched heartbeats use PATCH. Temporary delivery failures enter the bounded Outbox.

RelayTransport uses HTTPS with an Authorization bearer header. Routes include both the CAD session and game.JobId. Studio gets a generated server ID when JobId is empty. This keeps two game servers with the same user IDs apart.

The Node relay checks the session token, operation, body shape, and collection limits. It resolves timestamp markers, commits a complete next-state file by temporary-file rename, then acknowledges the write. A failed disk commit leaves the previous in-memory state intact. One process must own the file; this is not distributed storage.

The Electron main process reads snapshots using its CAD token. The existing renderer sends only the current session and authentication/access state through cad-bridge:context. Snapshot IPC accepts the primary CAD window's main frame only. Navigation, process loss, logout, and session changes invalidate context. A response that arrives after a context change is discarded.

RobloxFeed is inserted into the existing Calls view. It requests a snapshot every five seconds, cancels stale results on unmount/session change, and renders record text through React. It does not send actions back to Roblox, write Discord messages, or alter CAD duty/shift records.

The original Diff/Poller utilities and their tests remain available as unused core utilities. No poller or DispatchService starts in the game bootstrap.
