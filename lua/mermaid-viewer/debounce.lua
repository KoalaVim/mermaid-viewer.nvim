---@class mermaid_viewer.Debounce
local M = {}

local config = require("mermaid-viewer.config")

---@type table<number, table> augroup -> token of the watch that owns it; an older buffer attachment detaches itself
local owners = {}

---@param bufnr number Buffer to watch
---@param on_change fun() Callback to invoke after debounce
---@param name? string Group name suffix, so independent watchers on one buffer don't replace each other
---@return number augroup The autocmd group id (for cleanup)
function M.watch(bufnr, on_change, name)
  local group_name = "mermaid_viewer_debounce_" .. (name and (name .. "_") or "") .. bufnr
  local augroup = vim.api.nvim_create_augroup(group_name, { clear = true })
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

  -- terminal output does not trigger TextChanged
  if vim.bo[bufnr].buftype == "terminal" then
    local token = {}
    owners[augroup] = token
    vim.api.nvim_buf_attach(bufnr, false, {
      on_lines = function()
        if owners[augroup] ~= token then
          return true
        end
        vim.schedule(function()
          if owners[augroup] == token then
            schedule_render()
          end
        end)
      end,
    })
  end

  return augroup
end

---@param augroup number The autocmd group id returned by watch()
function M.stop(augroup)
  owners[augroup] = nil
  pcall(vim.api.nvim_del_augroup_by_id, augroup)
end

return M
