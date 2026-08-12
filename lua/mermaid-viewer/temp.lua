---@class mermaid_viewer.Temp
local M = {}

---@type string[]
local tracked = {}

local exit_cleanup_set_up = false

---@param path string
function M.track(path)
  tracked[#tracked + 1] = path
end

function M.cleanup()
  for _, path in ipairs(tracked) do
    os.remove(path)
  end
  tracked = {}
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
      M.cleanup()
    end,
  })
end

return M
