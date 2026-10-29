--!strict
--[=[
	LocationResolver: turns a player's character position into a dispatcher-friendly string,
	using CollectionService-tagged zone parts you place in Studio (see Config.zoneTag).
]=]

local CollectionService = game:GetService("CollectionService")

local Geo = require(script.Parent.Parent.Core.Geo)

local LocationResolver = {}

function LocationResolver.new(zoneTag: string, nearRadius: number): (Player) -> string
	return function(player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root == nil or not root:IsA("BasePart") then
			return "Unknown"
		end
		local zones: { Geo.Zone } = {}
		for _, instance in CollectionService:GetTagged(zoneTag) do
			if instance:IsA("BasePart") then
				local attribute = instance:GetAttribute("ZoneName")
				local name = if type(attribute) == "string" then attribute else instance.Name
				table.insert(
					zones,
					{ name = name, x = instance.Position.X, z = instance.Position.Z }
				)
			end
		end
		return Geo.describe(root.Position.X, root.Position.Z, zones, nearRadius)
	end
end

return LocationResolver
