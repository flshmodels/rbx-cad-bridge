--!strict
--[=[
	DispatchService: CAD -> players. Receives call diffs from the poller and tells a player when
	a dispatcher assigns them to a call.
]=]

local Players = game:GetService("Players")

local Mappers = require(script.Parent.Parent.Core.Mappers)
local Diff = require(script.Parent.Parent.Core.Diff)
local Notifier = require(script.Parent.Notifier)

local DispatchService = {}

local function describe(call: { [string]: any }): string
	local nature = if type(call.nature) == "string" then call.nature else "a call"
	local location = if type(call.location) == "string" then call.location else "unknown location"
	return `{nature} @ {location}`
end

function DispatchService.onCallsChanged(diff: Diff.Result, notify: Notifier.Notify)
	local function check(call: any, previous: any?)
		if type(call) ~= "table" then
			return
		end
		for _, player in Players:GetPlayers() do
			local nowAssigned = Mappers.isAssignedTo(call, player.UserId)
			local wasAssigned = previous ~= nil
				and type(previous) == "table"
				and Mappers.isAssignedTo(previous, player.UserId)
			if nowAssigned and not wasAssigned then
				notify(player, "dispatch", "Assigned: " .. describe(call))
			end
		end
	end

	for _, call in diff.added do
		check(call, nil)
	end
	for _, change in diff.changed do
		check(change.new, change.old)
	end
end

return DispatchService
