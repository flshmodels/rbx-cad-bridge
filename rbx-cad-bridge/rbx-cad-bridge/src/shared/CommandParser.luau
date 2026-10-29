--!strict
--[=[
	CommandParser: parses the text of the /911 chat command on the client.

	    /911 Shots fired | man with a handgun behind the gas station
	    /911 !high Vehicle pursuit | red sedan, northbound on Main
	    /911 !emergency Officer down

	This only shapes what we send. The server re-validates every field (Mappers.buildCall),
	because a client can always bypass this parser and fire the remote directly.
]=]

local CommandParser = {}

CommandParser.USAGE = "Usage: /911 [!low|!medium|!high|!emergency] <what's happening> | <details>"

local PRIORITIES: { [string]: boolean } =
	{ low = true, medium = true, high = true, emergency = true }

local function trim(text: string): string
	local trimmed = string.gsub(text, "^%s+", "")
	trimmed = string.gsub(trimmed, "%s+$", "")
	return trimmed
end

export type CallInput = { nature: string, description: string, priority: string? }

function CommandParser.parseCall(text: string): (CallInput?, string?)
	local body = string.gsub(text, "^%s*/%S+%s*", "")
	local priority: string? = nil

	local tag, rest = string.match(body, "^!(%a+)%s*(.*)$")
	if tag ~= nil and rest ~= nil then
		local lowered = string.lower(tag)
		if not PRIORITIES[lowered] then
			return nil, CommandParser.USAGE
		end
		priority = lowered
		body = rest
	end

	local rawNature, rawDescription = string.match(body, "^([^|]*)|?(.*)$")
	local nature = trim(rawNature or "")
	if nature == "" then
		return nil, CommandParser.USAGE
	end
	return { nature = nature, description = trim(rawDescription or ""), priority = priority }, nil
end

return CommandParser
