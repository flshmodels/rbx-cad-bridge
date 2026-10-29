--!strict
--[=[
	All tunables live here. This script is under ServerScriptService, so clients can never read
	it. Do NOT put your database secret in this file; use Secrets.luau (see Secrets.example).
]=]

return {
	-- Your Realtime Database root URL (no trailing path). Newer projects look like
	-- https://<name>-default-rtdb.firebaseio.com or https://<name>-default-rtdb.<region>.firebasedatabase.app
	databaseUrl = "https://YOUR-PROJECT-default-rtdb.firebaseio.com",

	-- true = log every request instead of sending it. Also forced on while databaseUrl is still
	-- the YOUR-PROJECT placeholder, so a fresh install is safe to run in Studio.
	dryRun = false,

	-- Where the bridge reads/writes in your database.
	paths = {
		calls = "calls",
		units = "units",
		panics = "panics",
	},

	-- Rename the bridge's canonical fields to the field names your CAD uses, per collection:
	--   fieldMap.calls = { nature = "type", description = "notes", location = "address" }
	-- Canonical call fields:  nature, description, priority, location, status, callerUserId,
	--                         callerName, createdAt, source
	-- Canonical unit fields:  userId, username, callsign, status, lastSeen, source
	-- Canonical panic fields: userId, username, callsign, location, status, createdAt, source
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
	pollInterval = 5,
	maxPollInterval = 60,
	heartbeatInterval = 60,
	flushInterval = 10,

	-- Writes that fail transiently wait here and are retried.
	outbox = { maxSize = 50, maxAgeSeconds = 300 },
}
