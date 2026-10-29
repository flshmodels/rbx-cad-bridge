--!strict
--[=[
	PanicService: on-duty units -> CAD panic record, plus an immediate in-game alert to every
	other on-duty unit (no need to wait for the next CAD poll).
]=]

local Players = game:GetService("Players")

local Mappers = require(script.Parent.Parent.Core.Mappers)
local CadClient = require(script.Parent.Parent.Core.CadClient)
local KeyedLimiter = require(script.Parent.Parent.Core.KeyedLimiter)
local RateLimiter = require(script.Parent.Parent.Core.RateLimiter)
local Notifier = require(script.Parent.Notifier)
local UnitService = require(script.Parent.UnitService)

local PanicService = {}

export type Deps = {
	client: CadClient.CadClient,
	remote: RemoteEvent,
	notify: Notifier.Notify,
	units: UnitService.Api,
	locationOf: (Player) -> string,
	now: () -> number,
	burst: number,
	refillSeconds: number,
}

function PanicService.start(deps: Deps)
	local limiter = KeyedLimiter.new(function()
		return RateLimiter.new(deps.burst, 1 / deps.refillSeconds, deps.now) :: any
	end)
	local counter = 0

	Players.PlayerRemoving:Connect(function(player)
		limiter:remove(player.UserId)
	end)

	deps.remote.OnServerEvent:Connect(function(player: Player)
		if not deps.units.isOnDuty(player) then
			deps.notify(player, "warn", "Only on-duty units can use the panic button.")
			return
		end
		if not limiter:allow(player.UserId) then
			return
		end

		local callsign = player:GetAttribute("CadCallsign")
		local caller: Mappers.Caller = {
			userId = player.UserId,
			username = player.Name,
			callsign = if type(callsign) == "string" then callsign else nil,
		}
		local location = deps.locationOf(player)
		counter += 1
		local id = Mappers.makeId(deps.now(), game.JobId, counter)

		local result = deps.client:createPanic(id, Mappers.buildPanic(caller, location))
		deps.units.setStatus(player, "panic")

		local label = caller.callsign or caller.username
		for _, unit in deps.units.onDutyPlayers() do
			if unit ~= player then
				deps.notify(unit, "panic", `PANIC: {label} at {location}`)
			end
		end
		if result.ok then
			deps.notify(player, "panic", "Panic sent to the CAD and on-duty units.")
		elseif result.queued then
			deps.notify(
				player,
				"panic",
				"Panic sent to units nearby; CAD is unreachable, retrying."
			)
		else
			warn(`[CadBridge] panic from {player.Name} rejected: {result.err}`)
			deps.notify(player, "warn", "Panic could not reach the CAD. Tell an admin.")
		end
	end)
end

return PanicService
