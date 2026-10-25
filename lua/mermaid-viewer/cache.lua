---@class mermaid_viewer.Cache
local M = {}

local temp = require("mermaid-viewer.temp")

---@type table<string, { width: number, height: number }> source hash -> natural render size in pixels
local naturals = {}

---@param source string
---@return string
function M.hash(source)
  return vim.fn.sha256(source)
end

--- Cache key for a render; width/height nil means natural size
---@param hash string
---@param width number|nil
---@param height number|nil
---@param theme string|nil
---@return string
function M.key(hash, width, height, theme)
  return vim.fn.sha256(table.concat({ hash, width or "natural", height or "natural", theme or "" }, "|"))
end

---@param key string
---@return string
function M.path(key)
  return temp.dir() .. "/" .. key .. ".png"
end

--- Path of the cached render, if it exists
---@param key string
---@return string|nil
function M.lookup(key)
  local path = M.path(key)
  if vim.uv.fs_stat(path) then
    return path
  end
end

---@param hash string
---@return number|nil aspect width / height of the natural render
function M.get_aspect(hash)
  local n = naturals[hash]
  return n and n.width / n.height
end

---@param hash string
---@return { width: number, height: number }|nil
function M.get_natural(hash)
  return naturals[hash]
end

---@param hash string
---@param width number
---@param height number
function M.set_natural(hash, width, height)
  naturals[hash] = { width = width, height = height }
end

--- Remove all cached files and forget natural sizes
function M.clear()
  naturals = {}
  temp.cleanup_all()
end

return M
