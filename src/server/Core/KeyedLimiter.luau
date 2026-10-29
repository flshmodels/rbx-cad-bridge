--!strict
--[=[
	KeyedLimiter: one limiter per key (e.g. per player UserId).

	Takes a factory so it has no dependency on a concrete limiter. Call `remove(key)` when the
	key goes away (PlayerRemoving) so the table cannot grow without bound.
]=]

local KeyedLimiter = {}
KeyedLimiter.__index = KeyedLimiter

export type Limiter = { tryAcquire: (any, number?) -> boolean }

type Fields = {
	factory: () -> Limiter,
	buckets: { [any]: Limiter },
}

export type KeyedLimiter = typeof(setmetatable({} :: Fields, KeyedLimiter))

function KeyedLimiter.new(factory: () -> Limiter): KeyedLimiter
	return setmetatable({ factory = factory, buckets = {} }, KeyedLimiter)
end

--- Returns true if `key` is allowed to act right now (and spends a token).
function KeyedLimiter.allow(self: KeyedLimiter, key: any): boolean
	local bucket = self.buckets[key]
	if bucket == nil then
		bucket = self.factory()
		self.buckets[key] = bucket
	end
	return bucket:tryAcquire(1)
end

function KeyedLimiter.remove(self: KeyedLimiter, key: any)
	self.buckets[key] = nil
end

return KeyedLimiter
