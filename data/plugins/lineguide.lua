-- mod-version:3
local common = require "core.common"
local command = require "core.command"
local config = require "core.config"
local style = require "core.style"
local DocView = require "core.docview"

---Configuration options for `lineguide` plugin.
---@class config.plugins.lineguide
---Disable or enable drawing of the line guide.
---@field enabled boolean
---Width in pixels of the line guide.
---@field width number
---The different column numbers for the line guides to draw.
---@field rulers table<integer,integer>
---Enable the utilization of a custom line color.
---@field use_custom_color boolean
---Applied when `use_custom_color` is enabled.
---@field custom_color renderer.color
config.plugins.lineguide = common.merge({
  enabled = false,
  width = 2,
  rulers = {
    -- 80,
    -- 100,
    -- 120,
    config.line_limit
  },
  use_custom_color = false,
  custom_color = style.selection,
  -- The config specification used by gui generators
  config_spec = {
    name = "Line Guide",
    {
      label = "Enabled",
      description = "Disable or enable drawing of the line guide.",
      path = "enabled",
      type = "toggle",
      default = true
    },
    {
      label = "Width",
      description = "Width in pixels of the line guide.",
      path = "width",
      type = "number",
      default = 2,
      min = 1
    },
    {
      label = "Ruler Positions",
      description = "The different column numbers for the line guides to draw.",
      path = "rulers",
      type = "list_strings",
      default = { tostring(config.line_limit) or "80" },
      get_value = function(rulers)
        if type(rulers) == "table" then
          local new_rulers = {}
          for _, ruler in ipairs(rulers) do
            table.insert(new_rulers, tostring(ruler))
          end
          return new_rulers
        else
          return { tostring(config.line_limit) }
        end
      end,
      set_value = function(rulers)
        local new_rulers = {}
        for _, ruler in ipairs(rulers) do
          local number = tonumber(ruler)
          if number then
            table.insert(new_rulers, number)
          end
        end
        if #new_rulers == 0 then
          table.insert(new_rulers, config.line_limit)
        end
        return new_rulers
      end
    },
    {
      label = "Use Custom Color",
      description = "Enable the utilization of a custom line color.",
      path = "use_custom_color",
      type = "toggle",
      default = false
    },
    {
      label = "Custom Color",
      description = "Applied when the above toggle is enabled.",
      path = "custom_color",
      type = "color",
      default = style.selection
    },
  }
}, config.plugins.lineguide)

local function get_ruler(v)
  local result = nil
  if type(v) == 'number' then
    result = { columns = v }
  elseif type(v) == 'table' then
    result = v
  end
  return result
end

local draw_overlay = DocView.draw_overlay
function DocView:draw_overlay(...)
  if
    type(config.plugins.lineguide) == "table"
    and
    config.plugins.lineguide.enabled
    and
    self:is(DocView)
  then
    local conf = config.plugins.lineguide
    local line_x = self:get_line_screen_position(1)
    local character_width = self:get_font():get_width("n")
    local ruler_width = config.plugins.lineguide.width
    local ruler_color = conf.use_custom_color and conf.custom_color
      or (style.guide or style.selection)

    for k,v in ipairs(config.plugins.lineguide.rulers) do
      local ruler = get_ruler(v)

      if ruler then
        local x = line_x + (character_width * ruler.columns)
        local y = self.position.y
        local w = ruler_width
        local h = self.size.y

        renderer.draw_rect(x, y, w, h, ruler.color or ruler_color)
      end
    end
  end
  -- everything else like the cursor above the line guides
  draw_overlay(self, ...)
end

command.add(nil, {
  ["lineguide:toggle"] = function()
    config.plugins.lineguide.enabled = not config.plugins.lineguide.enabled
  end
})
