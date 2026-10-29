# Changelog

## 0.3.0 — CAD starter project

- Remove the application-specific Electron adapter, UI patcher, and third-party session IDs.
- Use an arbitrary demo-session routing key and fictional event fixtures.
- Add an offline example, backend snapshot reader, and pure CAD field mapper.
- Document the transport contract, adaptation seams, inputs/outputs, trust boundaries, and verification limits.
- Keep the server-side validation, rate limits, retries, outbox, reference receiver, and protocol tests.

This is a reusable reference implementation. Connecting a real CAD still requires its own adapter and integration tests.
