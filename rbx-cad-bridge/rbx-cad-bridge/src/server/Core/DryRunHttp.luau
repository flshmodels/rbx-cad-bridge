--!strict
--[=[
	DryRunHttp: an HttpService stand-in that makes no network calls.

	Lets you run the whole bridge in Studio (or in tests) before you have a Firebase project:
	every request is logged (URL without its query string, so no token is ever printed) and
	answered with an empty-but-successful response. JSON helpers delegate to the real service.
]=]

local DryRunHttp = {}
DryRunHttp.__index = DryRunHttp

type Fields = { real: any, log: (string) -> () }
export type DryRunHttp = typeof(setmetatable({} :: Fields, DryRunHttp))

function DryRunHttp.new(real: any, log: (string) -> ()): DryRunHttp
	return setmetatable({ real = real, log = log }, DryRunHttp)
end

function DryRunHttp.RequestAsync(self: DryRunHttp, options: { [string]: any }): { [string]: any }
	local url = string.match(options.Url, "^[^?]*") or options.Url
	local body = if options.Body then " body=" .. options.Body else ""
	self.log(string.format("[dry-run] %s %s%s", options.Method, url, body))
	return { Success = true, StatusCode = 200, StatusMessage = "OK", Headers = {}, Body = "null" }
end

function DryRunHttp.JSONEncode(self: DryRunHttp, value: any): string
	return self.real:JSONEncode(value)
end

function DryRunHttp.JSONDecode(self: DryRunHttp, text: string): any
	return self.real:JSONDecode(text)
end

function DryRunHttp.UrlEncode(self: DryRunHttp, text: string): string
	return self.real:UrlEncode(text)
end

return DryRunHttp
