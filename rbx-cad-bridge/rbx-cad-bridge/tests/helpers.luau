--!strict
-- Test doubles: a scriptable fake HttpService and a manual clock.

local serde = require("@lune/serde")

local Helpers = {}

export type Response = {
	Success: boolean,
	StatusCode: number,
	Body: string?,
	Headers: { [string]: string }?,
}

--- A fake HttpService. Queue responses (or errors) with :push(); requests are recorded in
--- `requests`. When the queue is empty it answers 200 with "null".
function Helpers.fakeHttp()
	local http = { requests = {} :: { { [string]: any } }, queue = {} :: { any } }

	function http.push(self: any, item: any)
		table.insert(self.queue, item)
	end

	function http.RequestAsync(self: any, options: { [string]: any })
		table.insert(self.requests, options)
		local item = table.remove(self.queue, 1)
		if item == nil then
			return {
				Success = true,
				StatusCode = 200,
				StatusMessage = "OK",
				Headers = {},
				Body = "null",
			}
		end
		if item.throw then
			error(item.throw, 0)
		end
		return {
			Success = item.StatusCode >= 200 and item.StatusCode < 300,
			StatusCode = item.StatusCode,
			StatusMessage = "",
			Headers = item.Headers or {},
			Body = item.Body or "",
		}
	end

	function http.JSONEncode(_self: any, value: any): string
		return serde.encode("json", value)
	end

	function http.JSONDecode(_self: any, text: string): any
		return serde.decode("json", text)
	end

	function http.UrlEncode(_self: any, text: string): string
		return (
			string.gsub(text, "[^%w%-_%.~]", function(c)
				return string.format("%%%02X", string.byte(c))
			end)
		)
	end

	return http
end

--- A controllable clock. clock.now is read by clock.read; sleep(n) advances it.
function Helpers.manualClock()
	local clock = { now = 0, slept = {} :: { number } }
	function clock.read(): number
		return clock.now
	end
	function clock.sleep(seconds: number)
		table.insert(clock.slept, seconds)
		clock.now += seconds
	end
	return clock
end

return Helpers
