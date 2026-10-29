--!strict
--[=[
	RateLimiter: a token bucket.

	Roblox allows roughly 500 HttpService requests per minute per server, so every request the
	bridge makes must spend a token. `capacity` is the burst size, `refillPerSecond` the
	sustained rate. The clock is injected (seconds, monotonic) so the logic is testable.
]=]

local RateLimiter = {}
RateLimiter.__index = RateLimiter

type Fields = {
	capacity: number,
	refillPerSecond: number,
	tokens: number,
	last: number,
	clock: () -> number,
}

export type RateLimiter = typeof(setmetatable({} :: Fields, RateLimiter))

function RateLimiter.new(
	capacity: number,
	refillPerSecond: number,
	clock: () -> number
): RateLimiter
	assert(capacity > 0, "capacity must be positive")
	assert(refillPerSecond > 0, "refillPerSecond must be positive")
	return setmetatable({
		capacity = capacity,
		refillPerSecond = refillPerSecond,
		tokens = capacity,
		last = clock(),
		clock = clock,
	}, RateLimiter)
end

function RateLimiter._refill(self: RateLimiter)
	local now = self.clock()
	local elapsed = now - self.last
	if elapsed > 0 then
		self.tokens = math.min(self.capacity, self.tokens + elapsed * self.refillPerSecond)
		self.last = now
	end
end

--- Takes `cost` tokens (default 1) if available. Returns whether it succeeded.
function RateLimiter.tryAcquire(self: RateLimiter, cost: number?): boolean
	local n = cost or 1
	assert(n <= self.capacity, "cost exceeds bucket capacity")
	self:_refill()
	if self.tokens >= n then
		self.tokens -= n
		return true
	end
	return false
end

--- Seconds until `cost` tokens will be available (0 if available now).
function RateLimiter.timeUntil(self: RateLimiter, cost: number?): number
	local n = cost or 1
	self:_refill()
	if self.tokens >= n then
		return 0
	end
	return (n - self.tokens) / self.refillPerSecond
end

return RateLimiter
