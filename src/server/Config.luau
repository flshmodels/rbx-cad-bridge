--!strict
--[=[
	All tunables live here. This script is under ServerScriptService, so clients can never read
	it. Keep the relay game token in Secrets.luau (see Secrets.example).
]=]

return {
	-- Public HTTPS relay origin. A live Roblox server cannot reach your PC's localhost.
	relayUrl = "https://relay.example.com",
	-- An arbitrary deployment/session key shared by the game, relay, and CAD reader.
	sessionId = "demo-session",
	-- No requests leave Studio while this is true. Turn off only after configuring the relay.
	dryRun = true,

	-- Canonical relay collections. Keep these names unchanged for the bundled relay.
	paths = {
		calls = "calls",
		units = "units",
		panics = "panics",
	},

	-- Reserved for custom adapters. The bundled relay uses canonical names; leave empty.
	fieldMap = {
		calls = {} :: { [string]: string },
		units = {} :: { [string]: string },
		panics = {} :: { [string]: string },
	},

	-- Players on these Teams are registered as on-duty units in the CAD.
	dutyTeams = { "Police", "Sheriff" },

	-- Parts tagged with this CollectionService tag are dispatch zones. Give a part a "ZoneName"
	-- attribute (or it uses the part's Name). Calls then say "Courthouse [x, z]" instead of bare
	-- coordinates.
	zoneTag = "CadZone",
	nearRadius = 60, -- studs; beyond this the location reads "Near <zone>, ~N studs"

	-- HttpService allows ~500 requests/minute per server. Stay well under it.
	requestBudget = { burst = 20, perMinute = 300 },

	-- Per-player abuse limits.
	callLimit = { burst = 2, refillSeconds = 30 },
	panicLimit = { burst = 1, refillSeconds = 20 },

	-- Background loops (seconds).
	heartbeatInterval = 60,
	flushInterval = 10,

	-- Writes that fail transiently wait here and are retried.
	outbox = { maxSize = 50, maxAgeSeconds = 300 },
}
