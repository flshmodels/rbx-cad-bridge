--!strict
--[=[
	Poller: turns "GET this collection every N seconds" into change events.

	  * The first successful poll only records a baseline (so existing calls are not replayed
	    as "new" every time a server starts) unless emitInitial is set.
	  * Failures back off exponentially up to maxInterval, then recover to the normal interval.
	  * An error thrown by the change handler is caught so it cannot kill the loop.
	  * start()/stop() use a generation counter so a quick stop+start can never leave two loops.

	`step()` performs exactly one poll and is what the tests drive; `start()` just loops it.
]=]

local Poller = {}
Poller.__index = Poller

export type DiffResult = {
	added: { [string]: any },
	changed: { [string]: any },
	removed: { [string]: any },
}

export type Options = {
	name: string,
	fetch: () -> (boolean, { [string]: any }?, string?),
	diff: ({ [any]: any }?, { [any]: any }?) -> DiffResult,
	onChange: (DiffResult) -> (),
	interval: number,
	maxInterval: number,
	emitInitial: boolean?,
	sleep: (number) -> (),
	spawn: (() -> ()) -> (),
	log: ((string) -> ())?,
}

type Fields = {
	name: string,
	fetch: () -> (boolean, { [string]: any }?, string?),
	diff: ({ [any]: any }?, { [any]: any }?) -> DiffResult,
	onChange: (DiffResult) -> (),
	interval: number,
	maxInterval: number,
	emitInitial: boolean,
	sleep: (number) -> (),
	spawn: (() -> ()) -> (),
	log: (string) -> (),
	previous: { [string]: any },
	hasBaseline: boolean,
	failures: number,
	running: boolean,
	generation: number,
}

export type Poller = typeof(setmetatable({} :: Fields, Poller))

function Poller.new(options: Options): Poller
	return setmetatable({
		name = options.name,
		fetch = options.fetch,
		diff = options.diff,
		onChange = options.onChange,
		interval = options.interval,
		maxInterval = options.maxInterval,
		emitInitial = options.emitInitial or false,
		sleep = options.sleep,
		spawn = options.spawn,
		log = options.log or function() end,
		previous = {},
		hasBaseline = false,
		failures = 0,
		running = false,
		generation = 0,
	}, Poller)
end

local function hasChanges(result: DiffResult): boolean
	return next(result.added) ~= nil or next(result.changed) ~= nil or next(result.removed) ~= nil
end

--- One poll. Returns true if the fetch succeeded.
function Poller.step(self: Poller): boolean
	local ok, data, err = self.fetch()
	if not ok then
		self.failures += 1
		self.log(
			string.format(
				"[%s] poll failed (%d in a row): %s",
				self.name,
				self.failures,
				err or "?"
			)
		)
		return false
	end
	self.failures = 0
	local current = data or {}

	if not self.hasBaseline then
		self.hasBaseline = true
		if self.emitInitial then
			self:_emit(self.diff({}, current))
		end
		self.previous = current
		return true
	end

	local result = self.diff(self.previous, current)
	self.previous = current
	self:_emit(result)
	return true
end

function Poller._emit(self: Poller, result: DiffResult)
	if not hasChanges(result) then
		return
	end
	local handled, handlerErr = pcall(self.onChange :: (DiffResult) -> any, result)
	if not handled then
		self.log(string.format("[%s] change handler error: %s", self.name, tostring(handlerErr)))
	end
end

--- Seconds to wait before the next poll.
function Poller.nextDelay(self: Poller): number
	if self.failures == 0 then
		return self.interval
	end
	return math.min(self.maxInterval, self.interval * 2 ^ math.min(self.failures, 6))
end

function Poller.start(self: Poller)
	if self.running then
		return
	end
	self.running = true
	self.generation += 1
	local generation = self.generation
	self.spawn(function()
		while self.running and self.generation == generation do
			self:step()
			self.sleep(self:nextDelay())
		end
	end)
end

function Poller.stop(self: Poller)
	self.running = false
end

return Poller
