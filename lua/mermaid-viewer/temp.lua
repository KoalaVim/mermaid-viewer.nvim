---@class mermaid_viewer.Temp
local M = {}

---@type string[]
local tracked = {}

---@type string|nil
local plugin_dir

local exit_cleanup_set_up = false

--- Plugin-owned temporary directory (created on demand), removed on VimLeavePre
---@return string
function M.dir()
  if not plugin_dir or vim.fn.isdirectory(plugin_dir) == 0 then
    plugin_dir = vim.fn.tempname() .. "-mermaid-viewer"
    vim.fn.mkdir(plugin_dir, "p")
    M.setup_exit_cleanup()
  end
  return plugin_dir
end

---@param path string
function M.track(path)
  tracked[#tracked + 1] = path
end

--- Delete tracked files (cached renders in the plugin dir are kept)
function M.cleanup()
  for _, path in ipairs(tracked) do
    os.remove(path)
  end
  tracked = {}
end

--- Delete tracked files and the whole plugin dir
function M.cleanup_all()
  M.cleanup()
  if plugin_dir then
    vim.fn.delete(plugin_dir, "rf")
    plugin_dir = nil
  end
end

function M.setup_exit_cleanup()
  if exit_cleanup_set_up then
    return
  end
  exit_cleanup_set_up = true

  local augroup = vim.api.nvim_create_augroup("mermaid_viewer_temp_cleanup", { clear = true })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = augroup,
    callback = function()
      M.cleanup_all()
    end,
  })
end

return M
