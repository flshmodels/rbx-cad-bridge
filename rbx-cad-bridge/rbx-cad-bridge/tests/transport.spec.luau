--!strict
local serde = require("@lune/serde")
local T = require("./framework")
local Helpers = require("./helpers")
local Firebase = require("../src/server/Core/Firebase")
local RateLimiter = require("../src/server/Core/RateLimiter")
local Outbox = require("../src/server/Core/Outbox")
local CadClient = require("../src/server/Core/CadClient")
local Mappers = require("../src/server/Core/Mappers")
local Poller = require("../src/server/Core/Poller")
local Diff = require("../src/server/Core/Diff")
local DryRunHttp = require("../src/server/Core/DryRunHttp")

local TOKEN = "s3cr3t.token/with+chars"

local function makeFirebase(overrides: { [string]: any }?)
	local http = Helpers.fakeHttp()
	local clock = Helpers.manualClock()
	local options = {
		databaseUrl = "https://example-default-rtdb.firebaseio.com/",
		http = http,
		limiter = RateLimiter.new(100, 100, clock.read),
		backoff = function(attempt: number)
			return attempt
		end,
		sleep = clock.sleep,
		getAuth = function()
			return TOKEN
		end,
		maxRetries = 3,
	}
	for k, v in overrides or {} do
		(options :: any)[k] = v
	end
	return Firebase.new(options :: any), http, clock
end

T.describe("Firebase.validatePath", function()
	T.test("accepts normal paths", function()
		T.truthy((Firebase.validatePath("calls/0001_abc_0001")))
		T.truthy((Firebase.validatePath("units/123")))
	end)
	T.test("rejects traversal, empty segments and forbidden characters", function()
		for _, bad in
			{
				"",
				"/calls",
				"calls//x",
				"calls/a.b",
				"calls/$x",
				"calls/a#b",
				"calls/a[0]",
				"a/../b",
			}
		do
			T.eq((Firebase.validatePath(bad)), false, bad)
		end
	end)
end)

T.describe("Firebase requests", function()
	T.test("builds the URL with an encoded auth token and sorted query", function()
		local fb, http = makeFirebase()
		fb:get("calls", { orderBy = '"$key"', limitToLast = "5" })
		local url = http.requests[1].Url :: string
		T.eq(
			url,
			"https://example-default-rtdb.firebaseio.com/calls.json?auth=s3cr3t.token%2Fwith%2Bchars"
				.. "&limitToLast=5&orderBy=%22%24key%22"
		)
		T.eq(http.requests[1].Method, "GET")
		T.eq(http.requests[1].Body, nil)
	end)
	T.test("PUT sends JSON and asks for a silent response", function()
		local fb, http = makeFirebase()
		local result = fb:put("calls/abc", { nature = "Test" })
		T.truthy(result.ok)
		local request = http.requests[1]
		T.eq(request.Method, "PUT")
		T.truthy(string.find(request.Url, "print=silent", 1, true))
		T.deepEq(serde.decode("json", request.Body), { nature = "Test" })
	end)
	T.test("decodes JSON bodies and treats null as nil", function()
		local fb, http = makeFirebase()
		http:push({ StatusCode = 200, Body = '{"a":{"n":1}}' })
		T.deepEq(fb:get("calls").data, { a = { n = 1 } })
		http:push({ StatusCode = 200, Body = "null" })
		T.eq(fb:get("calls").data, nil)
	end)
	T.test("rejects an invalid path without touching the network", function()
		local fb, http = makeFirebase()
		local result = fb:put("calls/../x", { a = 1 })
		T.eq(result.ok, false)
		T.eq(result.retryable, false)
		T.eq(#http.requests, 0)
	end)
end)

T.describe("Firebase retries", function()
	T.test("retries 5xx and succeeds, sleeping with backoff between attempts", function()
		local fb, http, clock = makeFirebase()
		http:push({ StatusCode = 503 })
		http:push({ StatusCode = 502 })
		local result = fb:put("calls/a", { x = 1 })
		T.truthy(result.ok)
		T.eq(result.attempts, 3)
		T.deepEq(clock.slept, { 1, 2 })
	end)
	T.test("retries thrown network errors", function()
		local fb, http = makeFirebase()
		http:push({ throw = "HttpError: Timedout" })
		T.truthy(fb:put("calls/a", { x = 1 }).ok)
	end)
	T.test("gives up after maxRetries and reports a retryable failure", function()
		local fb, http = makeFirebase()
		for _ = 1, 10 do
			http:push({ StatusCode = 500 })
		end
		local result = fb:put("calls/a", { x = 1 })
		T.eq(result.ok, false)
		T.eq(result.retryable, true)
		T.eq(result.attempts, 4)
	end)
	T.test("does not retry permission errors and surfaces Firebase's message", function()
		local fb, http = makeFirebase()
		http:push({ StatusCode = 401, Body = '{"error":"Permission denied"}' })
		local result = fb:put("calls/a", { x = 1 })
		T.eq(result.ok, false)
		T.eq(result.retryable, false)
		T.eq(result.attempts, 1)
		T.eq(result.err, "HTTP 401: Permission denied")
	end)
	T.test("honours Retry-After on 429", function()
		local fb, http, clock = makeFirebase()
		http:push({ StatusCode = 429, Headers = { ["Retry-After"] = "7" } })
		T.truthy(fb:put("calls/a", { x = 1 }).ok)
		T.deepEq(clock.slept, { 7 })
	end)
	T.test("never retries POST", function()
		local fb, http = makeFirebase()
		http:push({ StatusCode = 500 })
		local result = fb:post("calls", { x = 1 })
		T.eq(result.ok, false)
		T.eq(result.attempts, 1)
		T.eq(#http.requests, 1)
	end)
	T.test("never leaks the auth token into errors", function()
		local fb, http = makeFirebase()
		for _ = 1, 4 do
			http:push({ throw = "failed fetching https://x/calls.json?auth=" .. TOKEN })
		end
		local result = fb:put("calls/a", { x = 1 })
		T.eq(string.find(result.err or "", TOKEN, 1, true), nil)
		T.truthy(string.find(result.err or "", "[REDACTED]", 1, true))
	end)
end)

T.describe("Firebase rate limiting", function()
	T.test("waits for a token instead of exceeding the budget", function()
		local clock = Helpers.manualClock()
		local limiter = RateLimiter.new(1, 1, clock.read)
		local fb, http = makeFirebase({ limiter = limiter, sleep = clock.sleep })
		fb:get("calls")
		fb:get("calls")
		T.eq(#http.requests, 2)
		T.truthy(clock.now >= 1, "second request should have waited ~1s for a token")
	end)
end)

--- A transport double for Outbox/CadClient tests.
local function fakeTransport(script: { any })
	local transport = { calls = {} :: { { [string]: any } } }
	function transport.request(self: any, method: string, path: string, body: any, query: any)
		table.insert(self.calls, { method = method, path = path, body = body, query = query })
		local result = table.remove(script, 1) or { ok = true, retryable = false }
		return result
	end
	return transport
end

T.describe("Outbox", function()
	local function make(script: { any }, maxSize: number?, maxAge: number?)
		local clock = Helpers.manualClock()
		local transport = fakeTransport(script)
		local dropped: { string } = {}
		local outbox = Outbox.new({
			transport = transport :: any,
			maxSize = maxSize or 10,
			maxAgeSeconds = maxAge or 100,
			clock = clock.read,
			onDrop = function(op, reason)
				table.insert(dropped, op.path .. ":" .. reason)
			end,
		})
		return outbox, transport, clock, dropped
	end

	T.test("replays in order and empties", function()
		local outbox, transport = make({})
		outbox:enqueue("PUT", "calls/1", { a = 1 })
		outbox:enqueue("PUT", "calls/2", { a = 2 })
		local sent, remaining = outbox:flush()
		T.eq(sent, 2)
		T.eq(remaining, 0)
		T.eq(transport.calls[1].path, "calls/1")
		T.eq(transport.calls[2].path, "calls/2")
	end)
	T.test("stops at the first transient failure to keep ordering", function()
		local outbox, transport = make({ { ok = false, retryable = true, err = "down" } })
		outbox:enqueue("PUT", "calls/1", {})
		outbox:enqueue("PUT", "calls/2", {})
		local sent, remaining = outbox:flush()
		T.eq(sent, 0)
		T.eq(remaining, 2)
		T.eq(#transport.calls, 1)
	end)
	T.test("drops permanently rejected writes and continues", function()
		local outbox, _, _, dropped = make({ { ok = false, retryable = false, err = "HTTP 403" } })
		outbox:enqueue("PUT", "calls/1", {})
		outbox:enqueue("PUT", "calls/2", {})
		local sent, remaining = outbox:flush()
		T.eq(sent, 1)
		T.eq(remaining, 0)
		T.deepEq(dropped, { "calls/1:rejected: HTTP 403" })
	end)
	T.test("expires old entries without sending them", function()
		local outbox, transport, clock, dropped = make({}, 10, 60)
		outbox:enqueue("PUT", "calls/old", {})
		clock.now += 61
		outbox:enqueue("PUT", "calls/new", {})
		outbox:flush()
		T.eq(#transport.calls, 1)
		T.eq(transport.calls[1].path, "calls/new")
		T.deepEq(dropped, { "calls/old:expired" })
	end)
	T.test("drops the oldest when full", function()
		local outbox, _, _, dropped = make({}, 2)
		outbox:enqueue("PUT", "calls/1", {})
		outbox:enqueue("PUT", "calls/2", {})
		outbox:enqueue("PUT", "calls/3", {})
		T.eq(outbox:size(), 2)
		T.deepEq(dropped, { "calls/1:queue full" })
	end)
end)

T.describe("CadClient", function()
	local schema = {
		paths = { calls = "calls", units = "units", panics = "panics" },
		fieldMap = { calls = { nature = "type", description = "notes" }, units = {}, panics = {} },
	}
	local function make(script: { any })
		local transport = fakeTransport(script)
		local queued: { string } = {}
		local outbox = {
			enqueue = function(_self: any, method: string, path: string)
				table.insert(queued, method .. " " .. path)
			end,
			flush = function()
				return 0, 0
			end,
			size = function()
				return #queued
			end,
		}
		local client = CadClient.new({
			transport = transport :: any,
			outbox = outbox :: any,
			schema = schema,
			remap = Mappers.remap,
			invert = Mappers.invert,
			serverTimestamp = Mappers.SERVER_TIMESTAMP,
		})
		return client, transport, queued
	end

	T.test("createCall PUTs a remapped record at calls/<id>", function()
		local client, transport = make({})
		local result =
			client:createCall("id1", { nature = "Shots", description = "d", status = "pending" })
		T.truthy(result.ok)
		local call = transport.calls[1]
		T.eq(call.method, "PUT")
		T.eq(call.path, "calls/id1")
		T.deepEq(call.body, { type = "Shots", notes = "d", status = "pending" })
	end)
	T.test("queues retryable failures and reports queued=true", function()
		local client, _, queued = make({ { ok = false, retryable = true, err = "down" } })
		local result = client:createCall("id1", { nature = "x" })
		T.eq(result.ok, false)
		T.eq(result.queued, true)
		T.deepEq(queued, { "PUT calls/id1" })
	end)
	T.test("does not queue permanent failures", function()
		local client, _, queued = make({ { ok = false, retryable = false, err = "HTTP 403" } })
		local result = client:createCall("id1", { nature = "x" })
		T.eq(result.queued, false)
		T.eq(#queued, 0)
	end)
	T.test("touchUnits is one multi-path PATCH", function()
		local client, transport = make({})
		client:touchUnits({ 1, 2 })
		T.eq(#transport.calls, 1)
		T.eq(transport.calls[1].method, "PATCH")
		T.eq(transport.calls[1].path, "units")
		T.deepEq(transport.calls[1].body, {
			["1/lastSeen"] = Mappers.SERVER_TIMESTAMP,
			["2/lastSeen"] = Mappers.SERVER_TIMESTAMP,
		})
		client:touchUnits({})
		T.eq(#transport.calls, 1, "empty list must not make a request")
	end)
	T.test("setUnitsOffline marks every unit in one request", function()
		local client, transport = make({})
		client:setUnitsOffline({ 5, 6 })
		T.eq(transport.calls[1].body["5/status"], "offline")
		T.eq(transport.calls[1].body["6/status"], "offline")
	end)
	T.test("fetchCalls maps CAD field names back to canonical names", function()
		local client, transport = make({})
		transport.request = function()
			return { ok = true, data = { abc = { type = "Shots", notes = "d" }, junk = 5 } }
		end
		local result = client:fetchCalls()
		T.truthy(result.ok)
		T.deepEq(result.data, { abc = { nature = "Shots", description = "d" } })
	end)
end)

T.describe("Poller", function()
	local function make(fetchResults: { any }, emitInitial: boolean?)
		local events: { any } = {}
		local logs: { string } = {}
		local clock = Helpers.manualClock()
		local poller = Poller.new({
			name = "test",
			fetch = function()
				local item = table.remove(fetchResults, 1)
				return item.ok, item.data, item.err
			end,
			diff = Diff.compute,
			onChange = function(diff)
				table.insert(events, diff)
			end,
			interval = 5,
			maxInterval = 60,
			emitInitial = emitInitial,
			sleep = clock.sleep,
			spawn = function(fn)
				fn()
			end,
			log = function(message)
				table.insert(logs, message)
			end,
		})
		return poller, events, logs, clock
	end

	T.test("first poll is a silent baseline, later polls emit diffs", function()
		local poller, events = make({
			{ ok = true, data = { a = { n = 1 } } },
			{ ok = true, data = { a = { n = 1 }, b = { n = 2 } } },
			{ ok = true, data = { a = { n = 1 }, b = { n = 2 } } },
		})
		poller:step()
		T.eq(#events, 0)
		poller:step()
		T.eq(#events, 1)
		T.deepEq(events[1].added, { b = { n = 2 } })
		poller:step()
		T.eq(#events, 1, "no change means no event")
	end)
	T.test("emitInitial reports existing records on the first poll", function()
		local poller, events = make({ { ok = true, data = { a = { n = 1 } } } }, true)
		poller:step()
		T.deepEq(events[1].added, { a = { n = 1 } })
	end)
	T.test("failures back off, then recover", function()
		local poller = make({
			{ ok = false, err = "down" },
			{ ok = false, err = "down" },
			{ ok = true, data = {} },
		})
		T.near(poller:nextDelay(), 5)
		poller:step()
		T.near(poller:nextDelay(), 10)
		poller:step()
		T.near(poller:nextDelay(), 20)
		poller:step()
		T.near(poller:nextDelay(), 5)
	end)
	T.test("a throwing handler does not break the poller", function()
		local logs: { string } = {}
		local fetches = {
			{ ok = true, data = {} },
			{ ok = true, data = { a = 1 } },
			{ ok = true, data = { a = 2 } },
		}
		local poller = Poller.new({
			name = "t",
			fetch = function()
				local item = table.remove(fetches, 1)
				return item.ok, item.data, nil
			end,
			diff = Diff.compute,
			onChange = function()
				error("boom")
			end,
			interval = 1,
			maxInterval = 1,
			sleep = function() end,
			spawn = function() end,
			log = function(m)
				table.insert(logs, m)
			end,
		})
		poller:step()
		T.truthy(poller:step())
		T.truthy(poller:step())
		T.truthy(string.find(logs[1], "boom", 1, true))
	end)
	T.test("start loops until stop, and restart does not leave two loops", function()
		local clock = Helpers.manualClock()
		local polls = 0
		local poller
		poller = Poller.new({
			name = "t",
			fetch = function()
				polls += 1
				if polls == 3 then
					poller:stop()
				end
				return true, {}, nil
			end,
			diff = Diff.compute,
			onChange = function() end,
			interval = 1,
			maxInterval = 1,
			sleep = clock.sleep,
			spawn = function(fn)
				fn()
			end,
		})
		poller:start()
		T.eq(polls, 3)
	end)
end)

T.describe("DryRunHttp", function()
	T.test("logs the request without its query string and answers successfully", function()
		local logs: { string } = {}
		local real = Helpers.fakeHttp()
		local dry = DryRunHttp.new(real, function(m)
			table.insert(logs, m)
		end)
		local response = dry:RequestAsync({
			Url = "https://x.firebaseio.com/calls/a.json?auth=SECRET",
			Method = "PUT",
			Body = "{}",
		})
		T.truthy(response.Success)
		T.eq(logs[1], "[dry-run] PUT https://x.firebaseio.com/calls/a.json body={}")
		T.eq(string.find(logs[1], "SECRET", 1, true), nil)
	end)
	T.test("works as the http object of a Firebase client end to end", function()
		local clock = Helpers.manualClock()
		local dry = DryRunHttp.new(Helpers.fakeHttp(), function() end)
		local fb = Firebase.new({
			databaseUrl = "https://x.firebaseio.com",
			http = dry,
			limiter = RateLimiter.new(10, 10, clock.read),
			backoff = function()
				return 0
			end,
			sleep = clock.sleep,
		})
		T.truthy(fb:put("calls/a", { x = 1 }).ok)
	end)
end)
