---@class mermaid_viewer.Navigation
local M = {}

local config = require("mermaid-viewer.config")
local state = require("mermaid-viewer.state")
local viewer = require("mermaid-viewer.viewer")
local source = require("mermaid-viewer.source")
local render = require("mermaid-viewer.render")
local display = require("mermaid-viewer.display")
local temp = require("mermaid-viewer.temp")

local PIXELS_PER_CELL = 100

---@param zoom_level number
local function rerender(zoom_level)
  local s = state.current
  if not s then
    return
  end

  local dims = viewer.get_dimensions()
  if not dims then
    return
  end

  local src, err = source.extract(s.source_buf)
  if not src then
    vim.notify(err or "Failed to extract mermaid source", vim.log.levels.ERROR, { title = "mermaid-viewer" })
    return
  end

  local width_px = math.floor(dims.width * PIXELS_PER_CELL * zoom_level)
  local height_px = math.floor(dims.height * PIXELS_PER_CELL * zoom_level)

  render.render(src, { width = width_px, height = height_px }, function(render_err, png_path, temp_input)
    if temp_input then
      temp.track(temp_input)
    end
    if render_err then
      vim.notify(render_err, vim.log.levels.ERROR, { title = "mermaid-viewer" })
      return
    end
    if png_path then
      temp.track(png_path)
      display.show(png_path, {
        width = math.floor(dims.width * zoom_level),
        height = math.floor(dims.height * zoom_level),
      })
    end
  end)
end

--- Zoom in one step. Re-renders at higher resolution.
function M.zoom_in()
  local s = state.current
  if not s then
    return
  end

  local opt = config.options
  s.zoom_level = math.min(s.zoom_level * opt.zoom_step, opt.max_zoom)
  rerender(s.zoom_level)
end

--- Zoom out one step. Re-renders at lower resolution.
function M.zoom_out()
  local s = state.current
  if not s then
    return
  end

  local opt = config.options
  s.zoom_level = math.max(s.zoom_level / opt.zoom_step, 1.0)
  rerender(s.zoom_level)
end

--- Reset zoom to 1.0x (fit-to-window).
function M.zoom_reset()
  local s = state.current
  if not s then
    return
  end

  s.zoom_level = 1.0
  s.pan_x = 0
  s.pan_y = 0
  rerender(s.zoom_level)
end

--- Pan in a direction.
---@param dx number Horizontal cell delta (positive = right)
---@param dy number Vertical cell delta (positive = down)
function M.pan(dx, dy)
  local s = state.current
  if not s then
    return
  end

  local dims = viewer.get_dimensions()
  if not dims then
    return
  end

  local opt = config.options
  local display_width = math.floor(dims.width * s.zoom_level)
  local display_height = math.floor(dims.height * s.zoom_level)

  s.pan_x = s.pan_x + dx * opt.pan_step
  s.pan_y = s.pan_y + dy * opt.pan_step

  -- Clamp so the image can't be panned past its edges
  s.pan_x = math.max(-(display_width - dims.width), math.min(0, s.pan_x))
  s.pan_y = math.max(-(display_height - dims.height), math.min(0, s.pan_y))

  display.move(s.pan_x, s.pan_y)
end

--- Set up keymaps on the given float buffer.
---@param float_buf number Buffer handle
function M.setup_keymaps(float_buf)
  local keys = config.options.keys

  local function map(key, action)
    vim.keymap.set("n", key, action, { buffer = float_buf, nowait = true })
  end

  map(keys.zoom_in, M.zoom_in)
  map(keys.zoom_out, M.zoom_out)
  map(keys.zoom_reset, M.zoom_reset)
  map(keys.pan_up, function() M.pan(0, -1) end)
  map(keys.pan_down, function() M.pan(0, 1) end)
  map(keys.pan_left, function() M.pan(-1, 0) end)
  map(keys.pan_right, function() M.pan(1, 0) end)
  for _, key in ipairs(keys.close) do
    map(key, function() require("mermaid-viewer").close() end)
  end
end

return M
