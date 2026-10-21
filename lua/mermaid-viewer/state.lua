---@class mermaid_viewer.State
local M = {}

---@type mermaid_viewer.ViewerState|nil
M.current = nil

--- The viewer whose first render is in flight (the float opens only after it succeeds)
---@type mermaid_viewer.ViewerState|nil
M.opening = nil

---@param s mermaid_viewer.ViewerState
---@return mermaid_viewer.ViewerState
function M.set(s)
  M.current = s
  return s
end

function M.clear()
  M.current = nil
end

---@return boolean
function M.is_active()
  return M.current ~= nil
end

return M
