-- Ported from upstream scripts/lua/tests/node.lua (#655, #659). amer-layer
-- does not carry upstream's node.lua test file, so only these cases are kept.
local core = require "core"
local Node = require "core.node"
local View = require "core.view"
local test = require "core.test"

test.describe("node redraw requests", function()
  test.before_each(function(context)
    context.active, context.last, context.next = core.active_view, core.last_active_view, core.next_active_view
    context.redraw = core.redraw
  end)

  test.after_each(function(context)
    core.active_view, core.last_active_view, core.next_active_view = context.active, context.last, context.next
    core.redraw = context.redraw
  end)

  test.it("a replacement view requests drawing after its first update only", function()
    local node = Node()
    node.size.x, node.size.y = 400, 300
    node.views, node.active_view = {View()}, nil
    node.active_view = node.views[1]
    node:update_layout()
    node:update(); node:update()
    local view = View()
    view.update = function() end
    node.views, node.active_view = {view}, view
    node:update_layout()
    core.redraw = false
    node:update()
    test.ok(core.redraw, "a newly updated view needs its first draw")
    core.redraw = false
    node:update()
    test.not_ok(core.redraw, "a settled view must stop requesting frames")
  end)

  for _, active in ipairs { true, false } do
    test.it("requests drawing when removing an " .. (active and "active" or "inactive") .. " tab", function()
      local node = Node()
      local first, second = View(), View()
      node:add_view(first)
      node:add_view(second)
      node:update_layout()
      node:update(); node:update()
      core.redraw = false
      node:close_view(node, active and second or first)
      test.ok(core.redraw, "removing a tab without an input event must repaint")
      test.equal(node.active_view, active and first or second)
      test.equal(#node.views, 1)
    end)
  end

  for _, direction in ipairs { "right", "down" } do
    test.it("requests drawing when closing a " .. direction .. " split", function()
      local node = Node()
      local content, panel = View(), View()
      node:add_view(content)
      local split = node:split(direction, panel)
      node:update_layout()
      node:update(); node:update()
      core.redraw = false
      split:close_view(node, panel)
      test.ok(core.redraw, "closing a split without an input event must repaint")
      test.equal(node.type, "leaf")
      test.equal(node.active_view, content)
    end)
  end
end)
