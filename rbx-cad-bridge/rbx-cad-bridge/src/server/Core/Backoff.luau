--!strict
--[=[
	Backoff: exponential backoff with "equal jitter".

	delay = ceiling/2 + random(0, ceiling/2), where ceiling = min(cap, base * 2^(attempt-1)).
	The floor of ceiling/2 guarantees we never retry instantly; the jitter spreads retries
	from many servers so they do not hammer the database in lockstep after an outage.

	Pure: the random source is injectable so tests are deterministic.
]=]

local Backoff = {}

function Backoff.delay(attempt: number, base: number, cap: number, rng: (() -> number)?): number
	local random = rng or function()
		return math.random()
	end
	local ceiling = math.min(cap, base * 2 ^ (math.max(attempt, 1) - 1))
	return ceiling / 2 + random() * (ceiling / 2)
end

return Backoff
