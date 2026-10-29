# Verification

The starter was prepared on 2026-10-29 as a CAD-independent reference project.

Result: 17 Node tests passed, the offline demo produced mapped JSON, and all CJS files passed JavaScript syntax checks. GitHub Actions also passed all 51 Luau tests, Selene lint, the Rojo build, and luau-lsp type checking on 2026-10-29. Live-game checks below remain pending.

Node tests exercise local HTTP delivery, separate session/server identities, read-only CAD credentials, event replay, heartbeat expiry, retention, persistence reload, failed disk commit rollback, and mapping. Mapper tests also cover identical event IDs across servers, malformed snapshots, optional fields, and the offline CLI example.

Locally available: Node. Not locally available/on PATH: Lune, Rojo, Selene, StyLua, luau-lsp. No software was downloaded or installed on the local computer. GitHub Actions installs its tools on an isolated runner. Automated checks do not validate live Roblox runtime behavior.

Pending integration checks: Roblox TextChatService/TextService behavior in a test game, team-change events, live HTTP delivery to public HTTPS, outage/replay tests in a game server, and adapter acceptance tests against a real CAD. No vendor-specific or Electron UI integration is claimed.

Before using the feed: run npm test and the Luau suite; exercise /911, duty changes and /panic in a published test game; verify duplicate upserts and session isolation; stop/restart the receiver and check recovery/stale-state display. Check the retention/queue limits against your requirements.
