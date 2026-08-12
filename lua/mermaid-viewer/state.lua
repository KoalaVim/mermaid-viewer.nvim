---@class mermaid_viewer.State
local M = {}

---@type mermaid_viewer.ViewerState|nil
M.current = nil

---@param source_buf number
---@param float_win number
---@param float_buf number
---@return mermaid_viewer.ViewerState
function M.create(source_buf, float_win, float_buf)
  M.current = {
    source_buf = source_buf,
    float_win = float_win,
    float_buf = float_buf,
    image = nil,
    zoom_level = 1.0,
    pan_x = 0,
    pan_y = 0,
    temp_files = {},
    render_timer = nil,
    augroup = 0,
  }
  return M.current
end

function M.clear()
  M.current = nil
end

---@return boolean
function M.is_active()
  return M.current ~= nil
end

return M
