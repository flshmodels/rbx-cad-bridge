--!strict
--[=[
	CadClient: the CAD-facing API the game services use. It owns the database layout and the
	schema mapping, and routes every write through the transport with an outbox fallback.

	Collections are addressed as <paths.X>/<id>, e.g. calls/00001761696000_ab12cd34_0001.
]=]

local CadClient = {}
CadClient.__index = CadClient

export type Transport = {
	request: (
		Transport,
		string,
		string,
		any?,
		{ [string]: string }?
	) -> {
		ok: boolean,
		status: number,
		data: any?,
		err: string?,
		retryable: boolean,
	},
}

export type OutboxLike = {
	enqueue: (OutboxLike, string, string, any?, { [string]: string }?) -> (),
	flush: (OutboxLike) -> (number, number),
	size: (OutboxLike) -> number,
}

export type Schema = {
	paths: { calls: string, units: string, panics: string },
	fieldMap: {
		calls: { [string]: string }?,
		units: { [string]: string }?,
		panics: { [string]: string }?,
	},
}

export type Options = {
	transport: Transport,
	outbox: OutboxLike,
	schema: Schema,
	remap: ({ [string]: any }, { [string]: string }?) -> { [string]: any },
	invert: ({ [string]: string }?) -> { [string]: string },
	serverTimestamp: { [string]: any },
	log: ((string) -> ())?,
}

export type WriteResult = { ok: boolean, queued: boolean, err: string? }
export type ReadResult = { ok: boolean, data: { [string]: any }?, err: string? }

type Fields = {
	transport: Transport,
	outbox: OutboxLike,
	schema: Schema,
	remap: ({ [string]: any }, { [string]: string }?) -> { [string]: any },
	invert: ({ [string]: string }?) -> { [string]: string },
	serverTimestamp: { [string]: any },
	log: (string) -> (),
}

export type CadClient = typeof(setmetatable({} :: Fields, CadClient))

function CadClient.new(options: Options): CadClient
	return setmetatable({
		transport = options.transport,
		outbox = options.outbox,
		schema = options.schema,
		remap = options.remap,
		invert = options.invert,
		serverTimestamp = options.serverTimestamp,
		log = options.log or function() end,
	}, CadClient)
end

function CadClient._write(self: CadClient, method: string, path: string, body: any?): WriteResult
	local result = self.transport:request(method, path, body, { print = "silent" })
	if result.ok then
		return { ok = true, queued = false, err = nil }
	end
	if result.retryable then
		self.outbox:enqueue(method, path, body, { print = "silent" })
		self.log(string.format("queued %s %s for retry (%s)", method, path, result.err or "?"))
		return { ok = false, queued = true, err = result.err }
	end
	return { ok = false, queued = false, err = result.err }
end

function CadClient._field(self: CadClient, collection: string, name: string): string
	local map = (self.schema.fieldMap :: any)[collection]
	return if map and map[name] then map[name] else name
end

function CadClient.createCall(self: CadClient, id: string, record: { [string]: any }): WriteResult
	local path = self.schema.paths.calls .. "/" .. id
	return self:_write("PUT", path, self.remap(record, self.schema.fieldMap.calls))
end

function CadClient.createPanic(self: CadClient, id: string, record: { [string]: any }): WriteResult
	local path = self.schema.paths.panics .. "/" .. id
	return self:_write("PUT", path, self.remap(record, self.schema.fieldMap.panics))
end

--- Creates or merges a unit record (PATCH keeps fields the CAD added, e.g. a callsign).
function CadClient.upsertUnit(
	self: CadClient,
	userId: number,
	record: { [string]: any }
): WriteResult
	local path = self.schema.paths.units .. "/" .. tostring(userId)
	return self:_write("PATCH", path, self.remap(record, self.schema.fieldMap.units))
end

function CadClient.setUnitStatus(self: CadClient, userId: number, status: string): WriteResult
	local path = self.schema.paths.units .. "/" .. tostring(userId)
	local body: { [string]: any } = {
		[self:_field("units", "status")] = status,
		[self:_field("units", "lastSeen")] = self.serverTimestamp,
	}
	return self:_write("PATCH", path, body)
end

--- One request refreshing lastSeen for many units (multi-path PATCH), so a heartbeat costs a
--- single request no matter how many players are on duty.
function CadClient.touchUnits(self: CadClient, userIds: { number }): WriteResult
	if #userIds == 0 then
		return { ok = true, queued = false, err = nil }
	end
	local field = self:_field("units", "lastSeen")
	local body: { [string]: any } = {}
	for _, userId in userIds do
		body[tostring(userId) .. "/" .. field] = self.serverTimestamp
	end
	return self:_write("PATCH", self.schema.paths.units, body)
end

function CadClient.setUnitsOffline(self: CadClient, userIds: { number }): WriteResult
	if #userIds == 0 then
		return { ok = true, queued = false, err = nil }
	end
	local statusField = self:_field("units", "status")
	local seenField = self:_field("units", "lastSeen")
	local body: { [string]: any } = {}
	for _, userId in userIds do
		body[tostring(userId) .. "/" .. statusField] = "offline"
		body[tostring(userId) .. "/" .. seenField] = self.serverTimestamp
	end
	return self:_write("PATCH", self.schema.paths.units, body)
end

function CadClient._read(self: CadClient, collection: "calls" | "units"): ReadResult
	local result = self.transport:request("GET", self.schema.paths[collection], nil, nil)
	if not result.ok then
		return { ok = false, data = nil, err = result.err }
	end
	local raw = result.data
	local out: { [string]: any } = {}
	if type(raw) == "table" then
		local inverse = self.invert((self.schema.fieldMap :: any)[collection])
		for id, record in raw do
			if type(record) == "table" then
				out[tostring(id)] = self.remap(record, inverse)
			end
		end
	end
	return { ok = true, data = out, err = nil }
end

--- Calls as the CAD stores them, translated back to canonical field names.
function CadClient.fetchCalls(self: CadClient): ReadResult
	return self:_read("calls")
end

function CadClient.fetchUnits(self: CadClient): ReadResult
	return self:_read("units")
end

function CadClient.flush(self: CadClient): (number, number)
	return self.outbox:flush()
end

return CadClient
