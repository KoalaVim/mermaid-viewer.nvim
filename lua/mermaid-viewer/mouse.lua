--- Mouse controls on the viewer float, like an image on a web page: drag to pan, the wheel scrolls (native),
--- Ctrl+wheel zooms toward the pointer, a click outside the float closes it.
---@class mermaid_viewer.Mouse
local M = {}

local config = require("mermaid-viewer.config")
local state = require("mermaid-viewer.state")
local viewer = require("mermaid-viewer.viewer")

---@type { col: number, row: number, left: number, top: number }|nil press position and view a drag started from
local drag
---@type { steps: number, focus: mermaid_viewer.Focus }|nil wheel zoom ticks waiting for the next event-loop turn
local pending

--- Grid cell under the pointer. Border clicks report line 0 and give no cell.
---@param s mermaid_viewer.ViewerState
---@param pos vim.fn.getmousepos.ret
---@return mermaid_viewer.Focus|nil
function M.focus(s, pos)
  if pos.winid ~= s.win or pos.line == 0 then
    return nil
  end
  local line = vim.api.nvim_buf_get_lines(s.buf, pos.line - 1, pos.line, false)[1] or ""
  -- a placeholder cell is one character plus its combining diacritics
  local gx = math.min(vim.fn.strcharlen(line:sub(1, pos.column - 1)), s.cols - 1)
  local gy = pos.line - 1
  local v = vim.api.nvim_win_call(s.win, vim.fn.winsaveview)
  return { gx = gx, gy = gy, ox = gx - v.leftcol, oy = gy - (v.topline - 1) }
end

---@return string
local function press()
  local s = state.current
  if not s then
    return "<LeftMouse>"
  end
  local pos = vim.fn.getmousepos()
  if pos.winid ~= s.win then
    drag = nil
    vim.schedule(function()
      require("mermaid-viewer").close()
    end)
    return "<LeftMouse>"
  end
  local v = vim.api.nvim_win_call(s.win, vim.fn.winsaveview)
  drag = { col = pos.screencol, row = pos.screenrow, left = v.leftcol, top = v.topline - 1 }
  return ""
end

---@return string
local function move()
  local s = state.current
  local d = drag
  if not s or not d then
    return "<LeftDrag>"
  end
  local pos = vim.fn.getmousepos()
  vim.schedule(function()
    if state.current == s then
      viewer.pan_to(s, d.left - (pos.screencol - d.col), d.top - (pos.screenrow - d.row))
    end
  end)
  return ""
end

--- Ctrl+wheel: zoom one step per tick toward the pointer. A burst of ticks is applied as one zoom.
---@param dir number 1 in, -1 out
local function wheel_zoom(dir)
  local s = state.current
  if not s then
    return
  end
  local focus = M.focus(s, vim.fn.getmousepos())
  if not focus then
    return
  end
  if pending then
    pending.steps, pending.focus = pending.steps + dir, focus
    return
  end
  pending = { steps = dir, focus = focus }
  vim.schedule(function()
    local p = pending
    pending = nil
    if state.current ~= s or s.closed then
      return
    end
    local target = s.zoom_req * config.options.zoom_step ^ p.steps
    target = math.max(1.0, math.min(target, viewer.zoom_cap(s.aspect)))
    if math.abs(target - s.zoom_req) > 1e-6 then
      require("mermaid-viewer.navigation").zoom_to(target, p.focus)
    end
  end)
end

---@param float_buf number
function M.setup_keymaps(float_buf)
  local function map(lhs, rhs, expr)
    vim.keymap.set("n", lhs, rhs, { buffer = float_buf, nowait = true, expr = expr })
  end
  drag, pending = nil, nil
  map("<LeftMouse>", press, true)
  map("<LeftDrag>", move, true)
  map("<LeftRelease>", function()
    local was = drag
    drag = nil
    return was and "" or "<LeftRelease>"
  end, true)
  -- a fast click must not select a word or line
  for _, n in ipairs({ "2", "3", "4" }) do
    map(("<%s-LeftMouse>"):format(n), "<Nop>")
  end
  map("<C-ScrollWheelUp>", function()
    wheel_zoom(1)
  end)
  map("<C-ScrollWheelDown>", function()
    wheel_zoom(-1)
  end)
end

return M
