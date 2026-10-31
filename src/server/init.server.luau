--!strict
-- Roblox game -> HTTPS receiver -> CAD backend. The feed is one-way.


local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Config)
local Remotes = require(ReplicatedStorage.CadBridgeShared.Remotes)

local Backoff = require(script.Core.Backoff)
local CadClient = require(script.Core.CadClient)
local DryRunHttp = require(script.Core.DryRunHttp)
local RelayTransport = require(script.Core.RelayTransport)
local Mappers = require(script.Core.Mappers)
local Outbox = require(script.Core.Outbox)
local RateLimiter = require(script.Core.RateLimiter)

local CallService = require(script.Services.CallService)
local LocationResolver = require(script.Services.LocationResolver)
local Notifier = require(script.Services.Notifier)
local PanicService = require(script.Services.PanicService)
local UnitService = require(script.Services.UnitService)

local function now(): number
	return DateTime.now().UnixTimestampMillis / 1000
end

local function log(message: string)
	warn("[CadBridge] " .. message)
end

-- Secrets ---------------------------------------------------------------------------------------
local authToken: string? = nil
local secretsModule = script:FindFirstChild("Secrets")
if secretsModule and secretsModule:IsA("ModuleScript") then
	local ok, secrets = pcall(require, secretsModule)
	if ok and type(secrets) == "table" and type(secrets.authToken) == "string" then
		authToken = secrets.authToken
	else
		log("Secrets module found but it does not return { authToken = <string> }")
	end
end

-- Dry run ---------------------------------------------------------------------------------------
local placeholderUrl = Config.relayUrl == "https://relay.example.com"
local dryRun = Config.dryRun or placeholderUrl
if dryRun then
	log("DRY RUN: no network requests will be made. Set Config.relayUrl to go live.")
elseif not HttpService.HttpEnabled then
	log("HttpService.HttpEnabled is false. Enable Game Settings > Security > Allow HTTP Requests.")
end
if not dryRun and authToken == nil then
	log(
		"No relay game token found. Copy Secrets.example.luau to Secrets.luau."
	)
end

-- Remotes ---------------------------------------------------------------------------------------
local remotesFolder = Instance.new("Folder")
remotesFolder.Name = Remotes.FOLDER_NAME
local function makeRemote(name: string): RemoteEvent
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remotesFolder
	return remote
end
local requestCallRemote = makeRemote(Remotes.RequestCall)
local panicRemote = makeRemote(Remotes.Panic)
local notifyRemote = makeRemote(Remotes.Notify)
remotesFolder.Parent = ReplicatedStorage

-- Core ------------------------------------------------------------------------------------------
assert(dryRun or (authToken ~= nil and #authToken >= 32), "Configure a relay game token before live mode")
local serverId = if game.JobId ~= "" then game.JobId else HttpService:GenerateGUID(false)

local http: any = if dryRun then DryRunHttp.new(HttpService, print) else HttpService

local transport = RelayTransport.new({
	relayUrl = Config.relayUrl,
	sessionId = Config.sessionId,
	serverId = serverId,
	http = http,
	limiter = RateLimiter.new(Config.requestBudget.burst, Config.requestBudget.perMinute / 60, now) :: any,
	backoff = function(attempt: number)
		return Backoff.delay(attempt, 1, 30)
	end,
	sleep = task.wait :: any,
	getAuth = function()
		return authToken
	end,
	maxRetries = 3,
	log = log,
})

local outbox = Outbox.new({
	transport = transport :: any,
	maxSize = Config.outbox.maxSize,
	maxAgeSeconds = Config.outbox.maxAgeSeconds,
	clock = now,
	onDrop = function(op, reason)
		log(`dropped queued {op.method} {op.path}: {reason}`)
	end,
})

local client = CadClient.new({
	transport = transport :: any,
	outbox = outbox :: any,
	schema = { paths = Config.paths, fieldMap = Config.fieldMap },
	remap = Mappers.remap,
	invert = Mappers.invert,
	serverTimestamp = Mappers.SERVER_TIMESTAMP,
	log = log,
})

-- Services --------------------------------------------------------------------------------------
local notify = Notifier.new(notifyRemote)
local locationOf = LocationResolver.new(Config.zoneTag, Config.nearRadius)

local units = UnitService.start({
	client = client,
	notify = notify,
	dutyTeams = Config.dutyTeams,
	heartbeatInterval = Config.heartbeatInterval,
})

CallService.start({
	client = client,
	remote = requestCallRemote,
	notify = notify,
	locationOf = locationOf,
	now = now,
	burst = Config.callLimit.burst,
	refillSeconds = Config.callLimit.refillSeconds,
})

PanicService.start({
	client = client,
	remote = panicRemote,
	notify = notify,
	units = units,
	locationOf = locationOf,
	now = now,
	burst = Config.panicLimit.burst,
	refillSeconds = Config.panicLimit.refillSeconds,
})

-- Outbox flush loop -----------------------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(Config.flushInterval)
		local sent, remaining = client:flush()
		if sent > 0 or remaining > 0 then
			log(`outbox: sent {sent}, {remaining} still queued`)
		end
	end
end)

-- Shutdown: mark units offline and give the outbox one last try (BindToClose allows ~30s) -------
game:BindToClose(function()
	units.shutdown()
	client:flush()
end)

log(`ready ({if dryRun then "dry run" else "live"})`)
