# Changelog

## 0.2.0 — Electron integration

- Replace the Firebase transport with a session- and game-server-scoped relay.
- Display Roblox 911 calls, game units, and panic alerts in the existing CAD Calls view.
- Follow the CAD selected session and login/access state over read-only IPC.
- Add file-backed relay storage, separate game-write and CAD-read tokens, schema checks, and integration tests.
- Document every public command, endpoint, configuration value, and return shape.

This release targets the NYSP-MDT testing#1 build reviewed at fef28ab. Roblox and Electron end-to-end tests remain manual; see docs/VERIFICATION.md.
