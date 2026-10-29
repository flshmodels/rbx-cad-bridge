--!strict
local Framework = require("./framework")
require("./core.spec")
require("./mappers.spec")
require("./transport.spec")
local ok = Framework.run()
if not ok then
	error("tests failed")
end
