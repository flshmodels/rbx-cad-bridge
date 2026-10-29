# Verification record

Prepared 2026-10-28 against the local NYSP-MDT testing#1 source reviewed at fef28ab.

## Checked locally

- 15 Node tests passed using actual loopback HTTP traffic and mocked Electron IPC objects.
- Tests cover game-to-CAD record flow, session/server isolation, read-only CAD credentials, duplicate-event handling, heartbeat staleness, TTL retention, schema checks, persistence reload, failed disk-commit rollback, IPC sender validation, logout/navigation, and in-flight session changes.
- JavaScript syntax checks run on the relay, Electron modules, preparation script, and prepared main.js.
- CAD preparation verifies exact integration anchors and writes a source/output hash manifest. It does not change the installed CAD.

## Not verified in this session

- Luau/Lune execution, StyLua formatting, Selene lint, luau-lsp analysis, and Rojo build: those tools were not installed/on PATH. No tools were downloaded or installed.
- Live Roblox game traffic and Roblox TextService/chat/team behavior.
- Running the updated installed Electron app, visual React rendering, and the complete CAD login-to-feed flow.
- Public HTTPS relay hosting, availability, or real credentials. No relay was deployed and nothing was pushed to GitHub.

## Manual acceptance check

1. Run the Luau checks with the existing toolchain or let GitHub CI run them.
2. Install the prepared shell/adapter/index into a test copy of the Electron CAD and configure a relay.
3. Set matching session IDs/tokens in Roblox, relay, and CAD. First confirm dry-run logs, then use a published test server and reachable HTTPS relay.
4. Send a 911 call, join/leave a duty team, and trigger panic on duty. Confirm the data appears in Calls within a refresh cycle after relay acceptance.
5. Open another session and confirm the first session's records disappear. Log out and verify the feed is cleared.
6. Stop the relay: the CAD should clear the feed/show unavailable, while failed Roblox writes queue. Restart before the queue expires and confirm retry delivery.
7. Restart the relay to confirm accepted events reload from its persistent file. Test heartbeat expiry if a game server exits without its final offline write.

This is a prepared integration, not a claim of live Roblox/Electron compatibility testing.
