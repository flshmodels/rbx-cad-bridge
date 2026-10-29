--!strict
--[=[
	Diff: compares two snapshots of a collection (id -> record).

	Roblox's HttpService cannot hold a streaming (SSE) connection, so the bridge polls and
	diffs. Only records that were added, changed or removed since the last poll produce events.
]=]

local Diff = {}

export type Change = { old: any, new: any }
export type Result = {
	added: { [string]: any },
	changed: { [string]: Change },
	removed: { [string]: any },
}

function Diff.deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in a do
		if not Diff.deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

function Diff.compute(previous: { [any]: any }?, current: { [any]: any }?): Result
	local result: Result = { added = {}, changed = {}, removed = {} }
	local before: { [any]: any } = previous or {}
	local after: { [any]: any } = current or {}
	for key, value in after do
		local id = tostring(key)
		local old = before[key]
		if old == nil then
			result.added[id] = value
		elseif not Diff.deepEqual(old, value) then
			result.changed[id] = { old = old, new = value }
		end
	end
	for key, value in before do
		if after[key] == nil then
			result.removed[tostring(key)] = value
		end
	end
	return result
end

function Diff.isEmpty(result: Result): boolean
	return next(result.added) == nil and next(result.changed) == nil and next(result.removed) == nil
end

return Diff
