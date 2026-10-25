---@class mermaid_viewer.Navigation
local M = {}

local config = require("mermaid-viewer.config")
local state = require("mermaid-viewer.state")
local viewer = require("mermaid-viewer.viewer")

local EPS = 1e-6

---@param zoom number
local function zoom_to(zoom)
  local s = state.current
  if not s then
    return
  end
  viewer.refresh(s, {
    zoom = zoom,
    on_error = function(err)
      vim.notify(err, vim.log.levels.ERROR, { title = "mermaid-viewer" })
    end,
    on_missing = function(err)
      vim.notify(err, vim.log.levels.ERROR, { title = "mermaid-viewer" })
    end,
  })
end

--- Zoom in one step, up to the configured maximum and the 297-cell grid cap
function M.zoom_in()
  local s = state.current
  if not s then
    return
  end
  local target = math.min(s.zoom_req * config.options.zoom_step, viewer.zoom_cap(s.aspect))
  if target > s.zoom_req + EPS then
    zoom_to(target)
  end
end

function M.zoom_out()
  local s = state.current
  if not s then
    return
  end
  local target = math.max(s.zoom_req / config.options.zoom_step, 1.0)
  if target < s.zoom_req - EPS then
    zoom_to(target)
  end
end

--- Back to fit-to-window with the view at the top-left
function M.zoom_reset()
  local s = state.current
  if not s then
    return
  end
  if s.zoom_req <= 1.0 + EPS and s.zoom <= 1.0 + EPS then
    vim.api.nvim_win_call(s.win, function()
      vim.fn.winrestview({ topline = 1, leftcol = 0, lnum = 1, col = 0, curswant = 0 })
    end)
    return
  end
  viewer.refresh(s, {
    reset = true,
    on_error = function(err)
      vim.notify(err, vim.log.levels.ERROR, { title = "mermaid-viewer" })
    end,
  })
end

--- Pan the current viewer by count steps
---@param dx number
---@param dy number
local function pan(dx, dy)
  local s = state.current
  if s then
    viewer.pan(s, dx * vim.v.count1, dy * vim.v.count1)
  end
end

--- Zoom, pan and close keymaps on the float buffer. h/j/k/l scroll the view; other native motions work as usual.
---@param float_buf number Buffer handle
function M.setup_keymaps(float_buf)
  local keys = config.options.keys

  local function map(key, action)
    vim.keymap.set("n", key, action, { buffer = float_buf, nowait = true })
  end

  map(keys.zoom_in, M.zoom_in)
  if keys.zoom_in == "+" then
    map("=", M.zoom_in)
  end
  map(keys.zoom_out, M.zoom_out)
  map(keys.zoom_reset, M.zoom_reset)
  map("h", function()
    pan(-1, 0)
  end)
  map("l", function()
    pan(1, 0)
  end)
  map("j", function()
    pan(0, 1)
  end)
  map("k", function()
    pan(0, -1)
  end)
  for _, key in ipairs(keys.close) do
    map(key, function()
      require("mermaid-viewer").close()
    end)
  end
end

return M
