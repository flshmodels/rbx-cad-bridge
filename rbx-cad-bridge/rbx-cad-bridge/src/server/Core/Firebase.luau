--!strict
--[=[
	Firebase: a small, dependency-injected client for the Firebase Realtime Database REST API.

	  * Every request spends a rate-limiter token (HttpService has a per-server request budget).
	  * Transient failures (network errors, HTTP 408/429/5xx) are retried with backoff and
	    honour Retry-After. Permanent failures (400/401/403/404...) are returned immediately.
	  * POST is never retried: a retry could create a duplicate. Use PUT with a client-chosen
	    key (see Mappers.makeId) for anything that must be safe to retry.
	  * Paths are validated, and the auth token is redacted from every error and log line.

	`http` is anything shaped like HttpService (RequestAsync, JSONEncode, JSONDecode,
	UrlEncode), which is how the unit tests run this module outside Roblox.
]=]

local Firebase = {}
Firebase.__index = Firebase

export type Limiter = {
	tryAcquire: (any, number?) -> boolean,
	timeUntil: (any, number?) -> number,
}

export type Result = {
	ok: boolean,
	status: number, -- HTTP status; 0 if no response was received
	data: any?,
	err: string?,
	retryable: boolean, -- true if the failure is transient (caller may queue and retry later)
	attempts: number,
}

export type Options = {
	databaseUrl: string,
	http: any,
	limiter: Limiter,
	backoff: (attempt: number) -> number,
	sleep: (seconds: number) -> (),
	getAuth: (() -> string?)?,
	maxRetries: number?,
	log: ((message: string) -> ())?,
}

type Fields = {
	baseUrl: string,
	http: any,
	limiter: Limiter,
	backoff: (number) -> number,
	sleep: (number) -> (),
	getAuth: (() -> string?)?,
	maxRetries: number,
	log: (string) -> (),
}

export type Firebase = typeof(setmetatable({} :: Fields, Firebase))

local WRITE_QUERY = { print = "silent" }

function Firebase.new(options: Options): Firebase
	local baseUrl = string.gsub(options.databaseUrl, "/+$", "")
	assert(string.sub(baseUrl, 1, 8) == "https://", "databaseUrl must start with https://")
	return setmetatable({
		baseUrl = baseUrl,
		http = options.http,
		limiter = options.limiter,
		backoff = options.backoff,
		sleep = options.sleep,
		getAuth = options.getAuth,
		maxRetries = options.maxRetries or 3,
		log = options.log or function() end,
	}, Firebase)
end

--- Firebase keys may not contain . $ # [ ] / or control characters, and may not be empty.
function Firebase.validatePath(path: string): (boolean, string?)
	if type(path) ~= "string" or path == "" or #path > 1500 then
		return false, "invalid path length"
	end
	for _, segment in string.split(path, "/") do
		if segment == "" or #segment > 768 or string.find(segment, "[%.%$#%[%]%c]") then
			return false, "invalid path segment: " .. string.sub(segment, 1, 40)
		end
	end
	return true, nil
end

local function fail(err: string, retryable: boolean, status: number, attempts: number): Result
	return {
		ok = false,
		status = status,
		data = nil,
		err = err,
		retryable = retryable,
		attempts = attempts,
	}
end

local function redact(text: string, secret: string?): string
	if secret == nil or secret == "" then
		return text
	end
	local escaped = string.gsub(secret, "%p", "%%%0")
	local out = string.gsub(text, escaped, "[REDACTED]")
	return out
end

function Firebase._buildUrl(self: Firebase, path: string, query: { [string]: string }?): string
	local params: { string } = {}
	local token = if self.getAuth then self.getAuth() else nil
	if token ~= nil and token ~= "" then
		table.insert(params, "auth=" .. self.http:UrlEncode(token))
	end
	if query ~= nil then
		local keys: { string } = {}
		for key in query do
			table.insert(keys, key)
		end
		table.sort(keys)
		for _, key in keys do
			table.insert(params, key .. "=" .. self.http:UrlEncode(query[key]))
		end
	end
	local url = self.baseUrl .. "/" .. path .. ".json"
	if #params > 0 then
		url ..= "?" .. table.concat(params, "&")
	end
	return url
end

function Firebase._waitForToken(self: Firebase): boolean
	for _ = 1, 200 do
		if self.limiter:tryAcquire(1) then
			return true
		end
		self.sleep(math.max(self.limiter:timeUntil(1), 0.05))
	end
	return false
end

local function retryAfterSeconds(headers: any): number?
	if type(headers) ~= "table" then
		return nil
	end
	for key, value in headers do
		if string.lower(tostring(key)) == "retry-after" then
			return tonumber(value)
		end
	end
	return nil
end

function Firebase.request(
	self: Firebase,
	method: string,
	path: string,
	body: any?,
	query: { [string]: string }?
): Result
	local pathOk, pathErr = Firebase.validatePath(path)
	if not pathOk then
		return fail(pathErr or "invalid path", false, 0, 0)
	end

	local payload: string? = nil
	if body ~= nil then
		local encoded, result = pcall(function()
			return self.http:JSONEncode(body)
		end)
		if not encoded then
			return fail("body could not be JSON-encoded", false, 0, 0)
		end
		payload = result
	end

	local token = if self.getAuth then self.getAuth() else nil
	local maxRetries = if method == "POST" then 0 else self.maxRetries
	local attempts = 0

	while true do
		attempts += 1
		if not self:_waitForToken() then
			return fail("rate limiter starved", true, 0, attempts)
		end

		local sent, response = pcall(function()
			return self.http:RequestAsync({
				Url = self:_buildUrl(path, query),
				Method = method,
				Headers = { ["Content-Type"] = "application/json" },
				Body = payload,
			})
		end)

		local failure: Result
		local waitHint: number? = nil
		if not sent then
			-- RequestAsync throws on network errors/timeouts; these are transient.
			failure = fail(redact(tostring(response), token), true, 0, attempts)
		elseif response.Success then
			local data: any = nil
			local text = response.Body
			if type(text) == "string" and text ~= "" and text ~= "null" then
				local decoded, value = pcall(function()
					return self.http:JSONDecode(text)
				end)
				if not decoded then
					return fail(
						"server returned invalid JSON",
						false,
						response.StatusCode,
						attempts
					)
				end
				data = value
			end
			return {
				ok = true,
				status = response.StatusCode,
				data = data,
				err = nil,
				retryable = false,
				attempts = attempts,
			}
		else
			local status: number = response.StatusCode
			local transient = status == 408 or status == 429 or status >= 500
			local detail = ""
			local decoded, value = pcall(function()
				return self.http:JSONDecode(response.Body)
			end)
			if decoded and type(value) == "table" and type(value.error) == "string" then
				detail = ": " .. string.sub(value.error, 1, 120)
			end
			failure = fail(string.format("HTTP %d%s", status, detail), transient, status, attempts)
			waitHint = retryAfterSeconds(response.Headers)
		end

		if not failure.retryable or attempts > maxRetries then
			return failure
		end
		local pause = self.backoff(attempts)
		if waitHint ~= nil then
			pause = math.max(pause, math.min(waitHint, 30))
		end
		self.log(
			string.format("retrying %s %s in %.1fs (%s)", method, path, pause, failure.err or "?")
		)
		self.sleep(pause)
	end
end

function Firebase.get(self: Firebase, path: string, query: { [string]: string }?): Result
	return self:request("GET", path, nil, query)
end

function Firebase.put(self: Firebase, path: string, body: any): Result
	return self:request("PUT", path, body, WRITE_QUERY)
end

--- PATCH merges. Keys may be multi-path ("123/status") to update several children at once.
function Firebase.patch(self: Firebase, path: string, body: any): Result
	return self:request("PATCH", path, body, WRITE_QUERY)
end

function Firebase.delete(self: Firebase, path: string): Result
	return self:request("DELETE", path, nil, WRITE_QUERY)
end

--- Not retried (could duplicate). Prefer put() with a client-generated key.
function Firebase.post(self: Firebase, path: string, body: any): Result
	return self:request("POST", path, body, nil)
end

return Firebase
