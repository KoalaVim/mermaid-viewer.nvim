---@class mermaid_viewer.Cache
local M = {}

local temp = require("mermaid-viewer.temp")

---@type table<string, number> source hash -> aspect (width / height)
local aspects = {}

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
---@return number|nil
function M.get_aspect(hash)
  return aspects[hash]
end

---@param hash string
---@param aspect number
function M.set_aspect(hash, aspect)
  aspects[hash] = aspect
end

--- Remove all cached files and forget aspects
function M.clear()
  aspects = {}
  temp.cleanup_all()
end

return M
