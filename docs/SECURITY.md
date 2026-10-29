# Security and trust boundaries

The game server validates RemoteEvent inputs, checks duty membership, derives identity/location, applies per-player limits, and filters player-supplied call text with Roblox TextService. Clients never receive the service token or choose receiver paths.

Each session has two independent random credentials. gameToken may write validated game events; cadToken may only read that session's snapshot. Tokens for another session are rejected. HTTP authorization uses a bearer header, not a URL query. There are no CAD-write/game-command endpoints.

Keep game credentials in ignored Secrets.luau under ServerScriptService and CAD credentials in your backend environment. Keep receiver credentials in its environment. Never bundle tokens in browser assets or share one token among unrelated communities. Place editors and people controlling a credential-bearing backend/desktop can recover those credentials.

The receiver validates fields/IDs, blocks prototype keys, bounds body and collection sizes, limits requests, and assigns timestamps. Its shared-token authorization identifies a service, not an individual officer. If you deploy it for multiple users, implement account authorization before showing records; consider short-lived scoped service credentials for larger deployments.

Use trusted HTTPS, protect the persistent state volume, and run only one process per state file. For multi-instance hosting, replace the file store with transactional shared storage and preserve idempotency. The example is not a certification or full security audit of a CAD.
