--!strict
--[=[
	CallService: players -> CAD. Handles the RequestCall remote.

	Order of checks (cheapest and most abuse-prone first):
	  1. payload is a table                       (a client can send anything)
	  2. per-player rate limit                    (before any validation work or HTTP)
	  3. field validation + sanitising            (Mappers.buildCall; server owns every field)
	  4. Roblox text filtering of player text     (it will be shown to other people)
	  5. write to the CAD with a client-chosen id (PUT, so a retry cannot duplicate the call)
]=]

local Players = game:GetService("Players")
local TextService = game:GetService("TextService")

local Mappers = require(script.Parent.Parent.Core.Mappers)
local CadClient = require(script.Parent.Parent.Core.CadClient)
local KeyedLimiter = require(script.Parent.Parent.Core.KeyedLimiter)
local RateLimiter = require(script.Parent.Parent.Core.RateLimiter)
local Notifier = require(script.Parent.Notifier)

local CallService = {}

export type Deps = {
	client: CadClient.CadClient,
	remote: RemoteEvent,
	notify: Notifier.Notify,
	locationOf: (Player) -> string,
	now: () -> number,
	burst: number,
	refillSeconds: number,
}

local function filterText(player: Player, text: string): string?
	if text == "" then
		return ""
	end
	local ok, result = pcall(function()
		local filtered =
			TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if ok and type(result) == "string" then
		return result
	end
	return nil
end

function CallService.start(deps: Deps)
	local limiter = KeyedLimiter.new(function()
		return RateLimiter.new(deps.burst, 1 / deps.refillSeconds, deps.now) :: any
	end)
	local counter = 0

	Players.PlayerRemoving:Connect(function(player)
		limiter:remove(player.UserId)
	end)

	deps.remote.OnServerEvent:Connect(function(player: Player, payload: unknown)
		if type(payload) ~= "table" then
			return
		end
		if not limiter:allow(player.UserId) then
			deps.notify(player, "warn", "Slow down - you are sending calls too quickly.")
			return
		end

		local callsign = player:GetAttribute("CadCallsign")
		local caller: Mappers.Caller = {
			userId = player.UserId,
			username = player.Name,
			callsign = if type(callsign) == "string" then callsign else nil,
		}
		local record, problem = Mappers.buildCall(payload :: any, caller, deps.locationOf(player))
		if record == nil then
			deps.notify(player, "warn", problem or "Invalid call.")
			return
		end

		local nature = filterText(player, record.nature)
		local description = filterText(player, record.description)
		if nature == nil or description == nil then
			deps.notify(player, "warn", "Your call could not be processed. Try again.")
			return
		end
		record.nature = nature
		record.description = description

		counter += 1
		local id = Mappers.makeId(deps.now(), game.JobId, counter)
		local result = deps.client:createCall(id, record)
		if result.ok then
			deps.notify(player, "info", "Your call was sent to dispatch.")
		elseif result.queued then
			deps.notify(
				player,
				"warn",
				"Dispatch is unreachable. Your call is queued and will retry."
			)
		else
			warn(`[CadBridge] call from {player.Name} rejected: {result.err}`)
			deps.notify(player, "warn", "Your call could not be sent. Tell an admin.")
		end
	end)
end

return CallService
