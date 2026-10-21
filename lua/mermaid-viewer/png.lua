---@class mermaid_viewer.Png
local M = {}

local SIGNATURE = "\137PNG\r\n\26\n"

---@param bytes string First 24+ bytes of a PNG file
---@return number|nil width
---@return number|string height_or_err
function M.parse_header(bytes)
  if #bytes < 24 or bytes:sub(1, 8) ~= SIGNATURE or bytes:sub(13, 16) ~= "IHDR" then
    return nil, "not a PNG"
  end
  local function u32(o)
    local a, b, c, d = bytes:byte(o, o + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
  end
  return u32(17), u32(21)
end

--- Read pixel dimensions from a PNG file's IHDR chunk
---@param path string
---@return number|nil width
---@return number|string height_or_err
function M.dimensions(path)
  local f, err = io.open(path, "rb")
  if not f then
    return nil, err
  end
  local bytes = f:read(24)
  f:close()
  return M.parse_header(bytes or "")
end

return M
