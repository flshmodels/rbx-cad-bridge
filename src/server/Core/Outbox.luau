--!strict
--[=[
	Outbox: a bounded in-memory queue for writes that failed for a transient reason.

	If the CAD (or the network) is briefly down, a 911 call should not vanish.
	Failed writes wait here and `flush()` replays them in order. The queue is bounded
	(oldest dropped first) and entries expire, so a long outage cannot exhaust memory or
	replay hours-old calls. A permanent failure (e.g. a 403) drops the entry instead of
	blocking everything behind it.

	Memory only: if the server shuts down with entries pending they are lost. See the README
	("Limitations") for why that is a deliberate trade-off.
]=]

local Outbox = {}
Outbox.__index = Outbox

export type Transport = {
	request: (
		Transport,
		string,
		string,
		any?,
		{ [string]: string }?
	) -> {
		ok: boolean,
		retryable: boolean,
		err: string?,
	},
}

export type Op = {
	method: string,
	path: string,
	body: any?,
	query: { [string]: string }?,
	enqueuedAt: number,
	tries: number,
}

export type Options = {
	transport: Transport,
	maxSize: number,
	maxAgeSeconds: number,
	clock: () -> number,
	onDrop: ((op: Op, reason: string) -> ())?,
}

type Fields = {
	transport: Transport,
	maxSize: number,
	maxAgeSeconds: number,
	clock: () -> number,
	onDrop: (Op, string) -> (),
	queue: { Op },
	flushing: boolean,
}

export type Outbox = typeof(setmetatable({} :: Fields, Outbox))

function Outbox.new(options: Options): Outbox
	return setmetatable({
		transport = options.transport,
		maxSize = options.maxSize,
		maxAgeSeconds = options.maxAgeSeconds,
		clock = options.clock,
		onDrop = options.onDrop or function() end,
		queue = {},
		flushing = false,
	}, Outbox)
end

function Outbox.size(self: Outbox): number
	return #self.queue
end

--- Queues a write. If the queue is full the oldest entry is dropped to make room.
function Outbox.enqueue(
	self: Outbox,
	method: string,
	path: string,
	body: any?,
	query: { [string]: string }?
)
	table.insert(self.queue, {
		method = method,
		path = path,
		body = body,
		query = query,
		enqueuedAt = self.clock(),
		tries = 0,
	})
	while #self.queue > self.maxSize do
		local dropped = table.remove(self.queue, 1) :: Op
		self.onDrop(dropped, "queue full")
	end
end

--- Replays queued writes in order. Stops at the first transient failure so ordering is kept.
--- Returns (sent, remaining).
function Outbox.flush(self: Outbox): (number, number)
	if self.flushing then
		return 0, #self.queue
	end
	self.flushing = true
	local sent = 0
	while true do
		local op = self.queue[1]
		if op == nil then
			break
		end
		if self.clock() - op.enqueuedAt > self.maxAgeSeconds then
			table.remove(self.queue, 1)
			self.onDrop(op, "expired")
			continue
		end
		local result = self.transport:request(op.method, op.path, op.body, op.query)
		if self.queue[1] ~= op then
			-- Dropped (queue overflow) while the request was in flight; move on.
			continue
		end
		if result.ok then
			table.remove(self.queue, 1)
			sent += 1
		elseif result.retryable then
			op.tries += 1
			break
		else
			table.remove(self.queue, 1)
			self.onDrop(op, "rejected: " .. tostring(result.err))
		end
	end
	self.flushing = false
	return sent, #self.queue
end

return Outbox
