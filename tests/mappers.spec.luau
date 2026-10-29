--!strict
local T = require("./framework")
local Mappers = require("../src/server/Core/Mappers")

local caller = { userId = 42, username = "Noah", callsign = nil }

T.describe("Mappers.sanitizeText", function()
	T.test("strips control chars, collapses whitespace and trims", function()
		T.eq(Mappers.sanitizeText("  hello\n\tworld \0 ", 50), "hello world")
	end)
	T.test("caps length by characters without splitting UTF-8", function()
		T.eq(Mappers.sanitizeText("héllo wörld", 5), "héllo")
	end)
	T.test("rejects non-strings and invalid UTF-8", function()
		T.eq(Mappers.sanitizeText(123, 10), nil)
		T.eq(Mappers.sanitizeText("bad\xff", 10), nil)
	end)
end)

T.describe("Mappers.buildCall", function()
	T.test("builds a valid record with defaults", function()
		local record, err = Mappers.buildCall({ nature = "Shots fired" }, caller, "Main St [0, 0]")
		T.eq(err, nil)
		local r = record :: any
		T.eq(r.nature, "Shots fired")
		T.eq(r.priority, "medium")
		T.eq(r.status, "pending")
		T.eq(r.source, "roblox")
		T.eq(r.callerUserId, 42)
		T.eq(r.location, "Main St [0, 0]")
		T.eq(r.createdAt[".sv"], "timestamp")
	end)
	T.test("rejects short nature, bad priority and non-text details", function()
		T.eq((select(1, Mappers.buildCall({ nature = "hi" }, caller, "x"))), nil)
		T.eq(
			(
				select(
					1,
					Mappers.buildCall({ nature = "Valid thing", priority = "urgent" }, caller, "x")
				)
			),
			nil
		)
		T.eq(
			(
				select(
					1,
					Mappers.buildCall({ nature = "Valid thing", description = { 1 } }, caller, "x")
				)
			),
			nil
		)
		T.eq((select(1, Mappers.buildCall({ nature = {} }, caller, "x"))), nil)
	end)
	T.test("ignores extra fields a client tries to smuggle in", function()
		local record = Mappers.buildCall(
			{ nature = "Valid thing", status = "closed", callerUserId = 1, ["../admin"] = true },
			caller,
			"x"
		) :: any
		T.eq(record.status, "pending")
		T.eq(record.callerUserId, 42)
		T.eq(record["../admin"], nil)
	end)
end)

T.describe("Mappers.buildUnit / buildPanic", function()
	T.test("validates unit status", function()
		local ok = Mappers.buildUnit(caller, "available")
		T.truthy(ok)
		local bad, err = Mappers.buildUnit(caller, "hacking")
		T.eq(bad, nil)
		T.truthy(err)
	end)
	T.test("panic record is active and server-timestamped", function()
		local panic = Mappers.buildPanic(caller, "Main St")
		T.eq(panic.status, "active")
		T.eq(panic.createdAt[".sv"], "timestamp")
	end)
end)

T.describe("Mappers.remap / invert", function()
	local map = { nature = "type", description = "notes" }
	T.test("renames mapped keys and keeps the rest", function()
		T.deepEq(
			Mappers.remap({ nature = "a", description = "b", status = "c" }, map),
			{ type = "a", notes = "b", status = "c" }
		)
	end)
	T.test("round-trips through invert", function()
		local original = { nature = "a", description = "b", status = "c" }
		T.deepEq(Mappers.remap(Mappers.remap(original, map), Mappers.invert(map)), original)
	end)
	T.test("nil map is a copy", function()
		local original = { a = 1 }
		local copy = Mappers.remap(original, nil)
		T.deepEq(copy, original)
		T.truthy(copy ~= original)
	end)
end)

T.describe("Mappers.isAssignedTo", function()
	T.test("supports map and list shapes, string and number ids", function()
		T.truthy(Mappers.isAssignedTo({ assigned = { ["42"] = true } }, 42))
		T.truthy(Mappers.isAssignedTo({ assigned = { 42, 7 } }, 42))
		T.truthy(Mappers.isAssignedTo({ assigned = { "42" } }, 42))
		T.eq(Mappers.isAssignedTo({ assigned = { ["42"] = false } }, 42), false)
		T.eq(Mappers.isAssignedTo({ assigned = { 7 } }, 42), false)
		T.eq(Mappers.isAssignedTo({}, 42), false)
	end)
end)

T.describe("Mappers.makeId", function()
	T.test("is sortable, fixed width and key-safe", function()
		local a = Mappers.makeId(1761696000, "ab12-cd34-ef56", 1)
		local b = Mappers.makeId(1761696001, "ab12-cd34-ef56", 1)
		T.eq(a, "01761696000_ab12cd34_0001")
		T.truthy(a < b)
		T.eq(string.find(a, "[%.%$#%[%]/]"), nil)
	end)
	T.test("falls back for empty JobId (Studio)", function()
		T.eq(Mappers.makeId(5, "", 12), "00000000005_studio_0012")
	end)
end)
