---@class mermaid_viewer.Debounce
local M = {}

local config = require("mermaid-viewer.config")

---@param bufnr number Buffer to watch
---@param on_change fun() Callback to invoke after debounce
---@return number augroup The autocmd group id (for cleanup)
function M.watch(bufnr, on_change)
  local augroup = vim.api.nvim_create_augroup("mermaid_viewer_debounce_" .. bufnr, { clear = true })
  ---@type uv_timer_t|nil
  local timer = nil

  local function cancel_timer()
    if timer then
      timer:stop()
      timer:close()
      timer = nil
    end
  end

  local function schedule_render()
    cancel_timer()
    timer = vim.uv.new_timer()
    timer:start(config.options.debounce_ms, 0, vim.schedule_wrap(function()
      timer:close()
      timer = nil
      on_change()
    end))
  end

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = augroup,
    buffer = bufnr,
    callback = schedule_render,
  })

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = augroup,
    buffer = bufnr,
    callback = function()
      cancel_timer()
      on_change()
    end,
  })

  return augroup
end

---@param augroup number The autocmd group id returned by watch()
function M.stop(augroup)
  pcall(vim.api.nvim_del_augroup_by_id, augroup)
end

return M
