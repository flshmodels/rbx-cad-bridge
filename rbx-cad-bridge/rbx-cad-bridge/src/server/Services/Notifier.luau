--!strict
--[=[
	Notifier: the one place that talks to players. Messages are length-capped so a long or odd
	string from the database can never flood a client.
]=]

local Notifier = {}

export type Kind = "info" | "warn" | "dispatch" | "panic"
export type Notify = (player: Player, kind: Kind, message: string) -> ()

function Notifier.new(remote: RemoteEvent): Notify
	return function(player, kind, message)
		if player.Parent == nil then
			return
		end
		remote:FireClient(player, kind, string.sub(message, 1, 200))
	end
end

return Notifier
