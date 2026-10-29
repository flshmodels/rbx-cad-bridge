--!strict
--[=[
	UnitService: keeps the CAD's unit list in sync with who is on duty in the game.

	  * A player becomes an on-duty unit when their Team is one of Config.dutyTeams, and goes
	    offline when they switch away or leave.
	  * One batched heartbeat request refreshes lastSeen for every on-duty unit, so the CAD can
	    tell a live unit from a stale record.
]=]

local Players = game:GetService("Players")

local Mappers = require(script.Parent.Parent.Core.Mappers)
local CadClient = require(script.Parent.Parent.Core.CadClient)
local Notifier = require(script.Parent.Notifier)

local UnitService = {}

export type Deps = {
	client: CadClient.CadClient,
	notify: Notifier.Notify,
	dutyTeams: { string },
	heartbeatInterval: number,
}

export type Api = {
	isOnDuty: (player: Player) -> boolean,
	onDutyPlayers: () -> { Player },
	setStatus: (player: Player, status: string) -> (),
	shutdown: () -> (),
}

local function callerOf(player: Player): Mappers.Caller
	local callsign = player:GetAttribute("CadCallsign")
	return {
		userId = player.UserId,
		username = player.Name,
		callsign = if type(callsign) == "string" then callsign else nil,
	}
end

function UnitService.start(deps: Deps): Api
	local onDuty: { [Player]: boolean } = {}

	local function isDutyTeam(player: Player): boolean
		local team: Team? = player.Team
		return team ~= nil and table.find(deps.dutyTeams, team.Name) ~= nil
	end

	local function setStatus(player: Player, status: string)
		local result = deps.client:setUnitStatus(player.UserId, status)
		if not result.ok and not result.queued then
			warn(`[CadBridge] could not set status for {player.Name}: {result.err}`)
		end
	end

	local function sync(player: Player)
		local duty = isDutyTeam(player)
		if duty and not onDuty[player] then
			onDuty[player] = true
			local record = Mappers.buildUnit(callerOf(player), "available")
			if record then
				deps.client:upsertUnit(player.UserId, record)
			end
		elseif not duty and onDuty[player] then
			onDuty[player] = nil
			setStatus(player, "offline")
		end
	end

	local function track(player: Player)
		player:GetPropertyChangedSignal("Team"):Connect(function()
			task.spawn(sync, player)
		end)
		task.spawn(sync, player)
	end

	Players.PlayerAdded:Connect(track)
	for _, player in Players:GetPlayers() do
		track(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		if onDuty[player] then
			onDuty[player] = nil
			task.spawn(setStatus, player, "offline")
		end
	end)

	local function onDutyPlayers(): { Player }
		local list = {}
		for player in onDuty do
			table.insert(list, player)
		end
		return list
	end

	-- Heartbeat: one batched request for all on-duty units.
	local running = true
	task.spawn(function()
		while running do
			task.wait(deps.heartbeatInterval)
			local ids = {}
			for _, player in onDutyPlayers() do
				table.insert(ids, player.UserId)
			end
			local result = deps.client:touchUnits(ids)
			if not result.ok and not result.queued then
				warn(`[CadBridge] heartbeat failed: {result.err}`)
			end
		end
	end)

	local function shutdown()
		running = false
		local ids = {}
		for _, player in onDutyPlayers() do
			table.insert(ids, player.UserId)
		end
		deps.client:setUnitsOffline(ids)
	end

	return {
		isOnDuty = function(player)
			return onDuty[player] == true
		end,
		onDutyPlayers = onDutyPlayers,
		setStatus = setStatus,
		shutdown = shutdown,
	}
end

return UnitService
