# Security model

## Threat model

| Threat | Mitigation |
|---|---|
| Exploiter fires the remotes directly, bypassing the chat parser | The server re-validates everything. The client only forwards text; `Mappers.buildCall` builds the record from validated pieces. |
| Exploiter spams calls or panics | Per-player token buckets (`KeyedLimiter`), checked before any validation or HTTP work. |
| Exploiter sends extra fields (`status`, `callerUserId`, `../admin`) | Ignored. Records are constructed field by field; the player never controls a path or a field name. |
| Exploiter sends huge, binary, or control-character text | Type-checked, UTF-8-validated, control characters stripped, length-capped. |
| Inappropriate text reaching other people through the CAD | Player text goes through `TextService:FilterStringAsync` before it is stored. |
| Civilian abuses the panic button | Server checks the player is an on-duty unit. |
| Server exhausts the `HttpService` budget | Global token bucket (`Config.requestBudget`) shared by every request. |
| Token leaks via error output or logs | Redacted from every error and log line; dry-run logs omit the query string. |
| Database path injection | Every path is validated (`Firebase.validatePath`). Keys containing `. $ # [ ] /` are rejected. |

## The token: read this

The bridge sends your token as `?auth=<token>`. It is stored in `src/server/Secrets.luau`
(gitignored), inside `ServerScriptService`, which Roblox never replicates to clients.

* A Firebase **database secret** works, but it grants **full admin access** to the database and bypasses
  your security rules. That is acceptable for a private community game where you control the server
  code, and **not** acceptable in a repo or game other people can fork or edit.
* Anyone who can edit the place (collaborators, plugin authors) can read `Secrets.luau`. Only give
  edit access to people you would trust with the database.
* **Do not commit the token.** If it ever lands in Git history, rotate it immediately; deleting the
  file does not remove it from history.
* Safer setups to consider: use a separate Firebase project (or database instance) just for the
  bridge, so a leak only exposes bridge data; or mint short-lived access tokens from a small service
  you control and have `Secrets.luau` supply those. The `getAuth` hook in `Firebase.new` accepts any
  function, so swapping the token source does not touch the rest of the code.

## What this does not protect against

* A compromised or malicious server script (anything running on your server has the token).
* Someone with the database token tampering with data directly. Treat CAD data as only as
  trustworthy as the token.
* Roblox-side moderation. The bridge filters text with Roblox's filter; it is not an anti-cheat.
