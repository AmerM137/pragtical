-- Ported from upstream scripts/lua/tests/net.lua (#686). amer-layer does not
-- carry upstream's net.lua test file (added in #677), so only this case is kept.
local net = require "net"
local test = require "core.test"

test.describe("net", function()
  test.test("rejects oversized network strings", function()
    test.error(function() net.set_cacert_path(string.rep("x", 1024)) end,
      "CA bundle path too long")
    test.error(function() net.resolve_address(string.rep("x", 254)) end,
      "hostname too long")
  end)
end)
