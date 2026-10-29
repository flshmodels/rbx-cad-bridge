--!strict
-- HTTPS relay transport. HTTP retries and the outbox share the same result contract.

local RelayTransport = {}
RelayTransport.__index = RelayTransport

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
	relayUrl: string,
	sessionId: string,
	serverId: string,
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

export type RelayTransport = typeof(setmetatable({} :: Fields, RelayTransport))

local WRITE_QUERY = { print = "silent" }

function RelayTransport.new(options: Options): RelayTransport
	local origin = string.gsub(options.relayUrl, "/+$", "")
	assert(string.match(origin, "^https://[%w%.%-]+$"), "relayUrl must be an HTTPS origin without a port or path")
	assert(string.match(options.sessionId, "^[%w_-]+$"), "invalid sessionId")
	assert(string.match(options.serverId, "^[%w_-]+$"), "invalid serverId")
	local baseUrl = origin .. "/v1/sessions/" .. options.sessionId .. "/servers/" .. options.serverId
	return setmetatable({
		baseUrl = baseUrl,
		http = options.http,
		limiter = options.limiter,
		backoff = options.backoff,
		sleep = options.sleep,
		getAuth = options.getAuth,
		maxRetries = options.maxRetries or 3,
		log = options.log or function() end,
	}, RelayTransport)
end

--- Only collection paths owned by CadClient are accepted.
function RelayTransport.validatePath(path: string): (boolean, string?)
	if type(path) ~= "string" or #path > 120 then
		return false, "invalid path"
	end
	local parts = string.split(path, "/")
	if #parts < 1 or #parts > 2 or not table.find({ "calls", "units", "panics" }, parts[1]) then
		return false, "invalid collection"
	end
	if #parts == 2 and (parts[2] == "" or not string.match(parts[2], "^[%w_-]+$")) then
		return false, "invalid record id"
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

function RelayTransport._buildUrl(self: RelayTransport, path: string, _query: { [string]: string }?): string
	return self.baseUrl .. "/" .. path
end

function RelayTransport._waitForToken(self: RelayTransport): boolean
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

function RelayTransport.request(
	self: RelayTransport,
	method: string,
	path: string,
	body: any?,
	query: { [string]: string }?
): Result
	local pathOk, pathErr = RelayTransport.validatePath(path)
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
				Headers = { ["Content-Type"] = "application/json", ["Authorization"] = "Bearer " .. (token or "") },
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
				detail = ": " .. string.sub(redact(value.error, token), 1, 120)
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

function RelayTransport.get(self: RelayTransport, path: string, query: { [string]: string }?): Result
	return self:request("GET", path, nil, query)
end

function RelayTransport.put(self: RelayTransport, path: string, body: any): Result
	return self:request("PUT", path, body, WRITE_QUERY)
end

--- The relay accepts a batched units PATCH for heartbeat/offline updates.
function RelayTransport.patch(self: RelayTransport, path: string, body: any): Result
	return self:request("PATCH", path, body, WRITE_QUERY)
end

function RelayTransport.delete(self: RelayTransport, path: string): Result
	return self:request("DELETE", path, nil, WRITE_QUERY)
end

--- Not retried (could duplicate). Prefer put() with a client-generated key.
function RelayTransport.post(self: RelayTransport, path: string, body: any): Result
	return self:request("POST", path, body, nil)
end

return RelayTransport
