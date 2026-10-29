# Access and data handling

Each session has two independent random credentials: gameToken may write validated Roblox events; cadToken may only read that session's snapshot. Authorization uses a bearer header, never a URL query string. A token for one session cannot access another. The relay rejects CAD writes and offers no commands back to Roblox.

Keep game tokens under ServerScriptService in ignored Secrets.luau. Keep desktop tokens in ignored cad-bridge.local.json, loaded by Electron's main process. Keep relay credentials in the environment. Do not upload local configs, .env files, or data/state.json. Place editors can read server scripts; people controlling the desktop can recover its token. Use a separate token for every session and role, and rotate compromised credentials.

This is a private-community shared-token model. The CAD's existing login/session check gates its UI, but the relay does not independently authenticate each CAD user. Someone who extracts a CAD token can read that session outside the app. Per-user relay access requires an authenticated backend and short-lived scoped tokens.

The game validates untrusted remote inputs, applies per-player limits, and filters player-supplied call text with Roblox TextService. The relay whitelists record fields, validates paths and user IDs, enforces request/storage limits, and rejects prototype keys. React renders imported strings as text. The Electron snapshot handler validates both the sender window and main frame; it rejects responses from superseded sessions.

Host the relay behind trusted HTTPS. For a proxy on a different machine, configure HOST deliberately and restrict direct HTTP access to the trusted network. Back up and restrict access to the persistent data volume. Run one relay process per state file. Existing CAD security settings are outside this update; this adapter does not imply an audit of the rest of the application.
