--!strict
--[=[
	Copy this file to Secrets.luau (same folder) and fill it in. Secrets.luau is gitignored, so
	your token is never committed. It lives under ServerScriptService, which clients cannot read.

	authToken is appended to requests as ?auth=<token>. It can be a Realtime Database secret or
	a short-lived access token you mint yourself. See docs/SECURITY.md for the trade-offs and
	for how to restrict what the bridge can touch.
]=]

return {
	authToken = "paste-your-token-here",
}
