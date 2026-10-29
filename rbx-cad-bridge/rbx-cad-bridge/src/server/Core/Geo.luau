--!strict
--[=[
	Geo: pure helpers for turning a world position into a dispatcher-friendly location string.
	Distance is measured on the horizontal (X/Z) plane; height is ignored.
]=]

local Geo = {}

export type Zone = { name: string, x: number, z: number }

--- Returns the nearest zone and its horizontal distance, or nil if there are no zones.
function Geo.nearest(x: number, z: number, zones: { Zone }): (Zone?, number?)
	local best: Zone? = nil
	local bestDist = math.huge
	for _, zone in zones do
		local dx, dz = zone.x - x, zone.z - z
		local dist = math.sqrt(dx * dx + dz * dz)
		if dist < bestDist then
			best, bestDist = zone, dist
		end
	end
	if best == nil then
		return nil, nil
	end
	return best, bestDist
end

--- "Main St (near)" when within `nearRadius`, otherwise "Near Main St, ~120 studs".
function Geo.describe(x: number, z: number, zones: { Zone }, nearRadius: number): string
	local zone, dist = Geo.nearest(x, z, zones)
	local coords = string.format("[%d, %d]", math.floor(x + 0.5), math.floor(z + 0.5))
	if zone == nil or dist == nil then
		return "Unknown " .. coords
	end
	if dist <= nearRadius then
		return string.format("%s %s", zone.name, coords)
	end
	return string.format("Near %s, ~%d studs %s", zone.name, math.floor(dist + 0.5), coords)
end

return Geo
