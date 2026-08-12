---@class mermaid_viewer.Display
local M = {}

local kitty = require("mermaid-viewer.kitty")
local viewer = require("mermaid-viewer.viewer")
local state = require("mermaid-viewer.state")

---@param s mermaid_viewer.ViewerState
---@return number row 1-indexed terminal row of float content area
---@return number col 1-indexed terminal column of float content area
local function get_screen_origin(s)
  local pos = vim.fn.win_screenpos(s.float_win)
  return pos[1], pos[2]
end

---@param png_path string Path to the PNG file
---@param opts? { width: number?, height: number? }
function M.show(png_path, opts)
  if not viewer.is_open() then
    return
  end

  local s = state.current
  if not s then
    return
  end

  opts = opts or {}

  local dims = viewer.get_dimensions()
  if not dims then
    return
  end

  local display_cols = opts.width or dims.width
  local display_rows = opts.height or dims.height

  local new_id = kitty.next_id()
  if not kitty.transmit(png_path, new_id) then
    vim.notify("Failed to read " .. png_path, vim.log.levels.ERROR, { title = "mermaid-viewer" })
    return
  end

  local row, col = get_screen_origin(s)
  kitty.display(new_id, row + s.pan_y, col + s.pan_x, display_cols, display_rows)

  if s.image then
    kitty.delete(s.image)
  end

  s.image = new_id
end

function M.clear()
  local s = state.current
  if s and s.image then
    kitty.delete(s.image)
    s.image = nil
  end
end

---@param x number X offset in cells
---@param y number Y offset in cells
function M.move(x, y)
  local s = state.current
  if not s or not s.image then
    return
  end

  local dims = viewer.get_dimensions()
  if not dims then
    return
  end

  local display_cols = math.floor(dims.width * s.zoom_level)
  local display_rows = math.floor(dims.height * s.zoom_level)

  local row, col = get_screen_origin(s)

  kitty.delete(s.image)
  kitty.display(s.image, row + y, col + x, display_cols, display_rows)
end

return M
