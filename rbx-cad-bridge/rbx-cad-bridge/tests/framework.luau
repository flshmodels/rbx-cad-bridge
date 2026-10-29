--!strict
-- A tiny test framework so the pure modules can be tested under Lune with no dependencies.

local Framework = {}

type Case = { name: string, fn: () -> () }
local cases: { Case } = {}
local currentGroup = ""

function Framework.describe(name: string, body: () -> ())
	local previous = currentGroup
	currentGroup = if previous == "" then name else previous .. " > " .. name
	body()
	currentGroup = previous
end

function Framework.test(name: string, fn: () -> ())
	table.insert(cases, { name = currentGroup .. " > " .. name, fn = fn })
end

local function show(value: any): string
	if type(value) == "table" then
		local parts = {}
		for k, v in value do
			table.insert(parts, tostring(k) .. "=" .. show(v))
		end
		table.sort(parts)
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return if type(value) == "string" then string.format("%q", value) else tostring(value)
end

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
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

function Framework.eq(actual: any, expected: any, message: string?)
	if actual ~= expected then
		error(
			string.format(
				"%sexpected %s, got %s",
				message and (message .. ": ") or "",
				show(expected),
				show(actual)
			),
			2
		)
	end
end

function Framework.deepEq(actual: any, expected: any, message: string?)
	if not deepEqual(actual, expected) then
		error(
			string.format(
				"%sexpected %s, got %s",
				message and (message .. ": ") or "",
				show(expected),
				show(actual)
			),
			2
		)
	end
end

function Framework.truthy(value: any, message: string?)
	if not value then
		error(message or "expected a truthy value", 2)
	end
end

function Framework.near(actual: number, expected: number, tolerance: number?)
	if math.abs(actual - expected) > (tolerance or 1e-9) then
		error(string.format("expected %s ≈ %s", tostring(actual), tostring(expected)), 2)
	end
end

function Framework.run(): boolean
	local failed = 0
	for _, case in cases do
		local ok, err = pcall(case.fn :: () -> any)
		if ok then
			print("  ✓ " .. case.name)
		else
			failed += 1
			print("  ✗ " .. case.name)
			print("      " .. tostring(err))
		end
	end
	print(string.format("\n%d passed, %d failed", #cases - failed, failed))
	return failed == 0
end

return Framework
