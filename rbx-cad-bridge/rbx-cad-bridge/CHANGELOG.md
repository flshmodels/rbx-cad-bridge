# Changelog

## 0.1.0

Initial release.

- Firebase Realtime Database REST transport with rate limiting, retry/backoff, token redaction
- Outbox for transient write failures
- CallService (`/911`), PanicService (`/panic`), UnitService (duty sync + heartbeat), DispatchService
- Poller + Diff for CAD-to-game events
- Configurable schema mapping
- Dry-run mode
- Lune test suite, CI
