--!strict
--[=[
	Mappers: validation, sanitising and schema mapping. Pure functions, no Roblox APIs.

	Everything a player types is untrusted. Records are built here, from validated pieces, and
	the player never controls a database path or a field name.

	Schema mapping: the bridge works with canonical field names (nature, description, ...).
	`remap` translates them to whatever your CAD actually uses (see Config.fieldMap), and
	`invert` + `remap` translates records read back from the CAD.
]=]

local Mappers = {}

export type Priority = "low" | "medium" | "high" | "emergency"
export type Caller = { userId: number, username: string, callsign: string? }

Mappers.PRIORITIES = { low = true, medium = true, high = true, emergency = true }
Mappers.UNIT_STATUSES = {
	offline = true,
	available = true,
	busy = true,
	en_route = true,
	on_scene = true,
	panic = true,
}

Mappers.SERVER_TIMESTAMP = { ["$timestamp"] = true }

--- Strips control characters, collapses whitespace, trims, and caps length (in characters).
--- Returns nil if the value is not a string or is not valid UTF-8.
function Mappers.sanitizeText(value: any, maxLen: number): string?
	if type(value) ~= "string" then
		return nil
	end
	local len = utf8.len(value)
	if len == nil then
		return nil
	end
	local text = string.gsub(value, "%c", " ")
	text = string.gsub(text, "%s+", " ")
	text = string.gsub(text, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	local textLen = utf8.len(text) :: number
	if textLen > maxLen then
		local cut = utf8.offset(text, maxLen + 1)
		text = string.sub(text, 1, (cut :: number) - 1)
		text = string.gsub(text, "%s+$", "")
	end
	return text
end

--- Builds a call record from untrusted player input. Returns (record, nil) or (nil, error).
function Mappers.buildCall(
	input: { [string]: any },
	caller: Caller,
	location: string
): ({ [string]: any }?, string?)
	local nature = Mappers.sanitizeText(input.nature, 80)
	if nature == nil or (utf8.len(nature) :: number) < 3 then
		return nil, "Describe what is happening (3-80 characters)."
	end
	local description = Mappers.sanitizeText(input.description or "", 300)
	if description == nil then
		return nil, "Details must be plain text (max 300 characters)."
	end
	local priority = input.priority or "medium"
	if type(priority) ~= "string" or not Mappers.PRIORITIES[priority] then
		return nil, "Priority must be low, medium, high or emergency."
	end
	return {
		source = "roblox",
		nature = nature,
		description = description,
		priority = priority,
		location = location,
		status = "pending",
		callerUserId = caller.userId,
		callerName = caller.username,
		createdAt = Mappers.SERVER_TIMESTAMP,
	},
		nil
end

function Mappers.buildPanic(caller: Caller, location: string): { [string]: any }
	return {
		source = "roblox",
		userId = caller.userId,
		username = caller.username,
		callsign = caller.callsign,
		location = location,
		status = "active",
		createdAt = Mappers.SERVER_TIMESTAMP,
	}
end

function Mappers.buildUnit(caller: Caller, status: string): ({ [string]: any }?, string?)
	if not Mappers.UNIT_STATUSES[status] then
		return nil, "Unknown unit status: " .. tostring(status)
	end
	return {
		source = "roblox",
		userId = caller.userId,
		username = caller.username,
		callsign = caller.callsign,
		status = status,
		lastSeen = Mappers.SERVER_TIMESTAMP,
	},
		nil
end

--- Renames the top-level keys of `record` using `map` (unmapped keys are kept as-is).
function Mappers.remap(record: { [string]: any }, map: { [string]: string }?): { [string]: any }
	if map == nil then
		return table.clone(record)
	end
	local out = {}
	for key, value in record do
		out[map[key] or key] = value
	end
	return out
end

function Mappers.invert(map: { [string]: string }?): { [string]: string }
	local out: { [string]: string } = {}
	local source: { [string]: string } = map or {}
	for from, to in source do
		out[to] = from
	end
	return out
end

--- True if `call.assigned` names this user, either as a map {["123"]=true} or a list {123}.
function Mappers.isAssignedTo(call: { [string]: any }, userId: number): boolean
	local assigned = call.assigned
	if type(assigned) ~= "table" then
		return false
	end
	local wanted = tostring(userId)
	for key, value in assigned do
		if tostring(key) == wanted and value then
			return true
		end
		if tostring(value) == wanted then
			return true
		end
	end
	return false
end

--- Client-generated, lexicographically time-ordered key. Using our own keys with PUT makes
--- retries idempotent: re-sending the same call overwrites it instead of duplicating it.
function Mappers.makeId(now: number, jobId: string, counter: number): string
	local alnum = string.gsub(jobId, "[^%w]", "")
	local short = string.sub(alnum, 1, 8)
	if short == "" then
		short = "studio"
	end
	return string.format("%011d_%s_%04d", math.floor(now), short, counter % 10000)
end

return Mappers
