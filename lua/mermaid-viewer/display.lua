---@class mermaid_viewer.Display
local M = {}

local viewer = require("mermaid-viewer.viewer")
local state = require("mermaid-viewer.state")

--- Display a rendered PNG in the viewer float.
--- Implements double-buffered swap: new image renders before old clears.
---@param png_path string Path to the PNG file
---@param opts? { width: number?, height: number? } Override display dimensions in cells
function M.show(png_path, opts)
  if not viewer.is_open() then
    return
  end

  local s = state.current
  if not s then
    return
  end

  opts = opts or {}

  local display_width = opts.width
  local display_height = opts.height

  if not display_width or not display_height then
    local dims = viewer.get_dimensions()
    if not dims then
      return
    end
    display_width = display_width or dims.width
    display_height = display_height or dims.height
  end

  local image = require("image")
  local new_image = image.from_file(png_path, {
    window = s.float_win,
    buffer = s.float_buf,
    x = s.pan_x,
    y = s.pan_y,
    width = display_width,
    height = display_height,
  })

  if not new_image then
    vim.notify("Failed to create image from " .. png_path, vim.log.levels.ERROR, { title = "mermaid-viewer" })
    return
  end

  new_image:render()

  -- Double buffer: clear old image after new one is rendered to avoid flicker
  if s.image then
    s.image:clear()
  end

  s.image = new_image
end

--- Clear the currently displayed image
function M.clear()
  local s = state.current
  if s and s.image then
    s.image:clear()
    s.image = nil
  end
end

--- Reposition the current image (for pan operations)
---@param x number X offset in cells
---@param y number Y offset in cells
function M.move(x, y)
  local s = state.current
  if s and s.image then
    s.image:move(x, y)
  end
end

return M
