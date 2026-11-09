---@class mermaid_viewer.Debounce
local M = {}

local config = require("mermaid-viewer.config")

---@type table<number, table> augroup -> token of the watch that owns it; an older buffer attachment detaches itself
local owners = {}
local cleanup = {}

---@param bufnr number Buffer to watch
---@param on_change fun() Callback to invoke after debounce
---@param name? string Group name suffix, so independent watchers on one buffer don't replace each other
---@return number augroup The autocmd group id (for cleanup)
function M.watch(bufnr, on_change, name, opts)
  opts = opts or {}
  local group_name = "mermaid_viewer_debounce_" .. (name and (name .. "_") or "") .. bufnr
  local augroup = vim.api.nvim_create_augroup(group_name, { clear = true })
  if cleanup[augroup] then
    cleanup[augroup]()
  end
  local token = {}
  owners[augroup] = token
  ---@type uv_timer_t|nil
  local timer = nil

  local function cancel_timer()
    if timer then
      timer:stop()
      timer:close()
      timer = nil
    end
  end

  cleanup[augroup] = cancel_timer

  local function schedule_render()
    local throttle = opts.throttle_ms and opts.throttle_ms()
    if opts.on_dirty then
      opts.on_dirty()
    end
    if throttle and timer then
      return
    end
    cancel_timer()
    local current = vim.uv.new_timer()
    timer = current
    current:start(throttle or config.options.debounce_ms, 0, vim.schedule_wrap(function()
      if timer ~= current then
        return
      end
      current:close()
      timer = nil
      if owners[augroup] ~= token then
        return
      end
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

  -- Sidekick can set FileType before jobstart(term=true). In that case the watcher exists before
  -- the buffer becomes a terminal; attach on TermOpen rather than relying on TextChanged in normal mode.
  local attached = false
  local function attach_terminal()
    if attached or owners[augroup] ~= token then
      return
    end
    attached = true
    local queued = false
    vim.api.nvim_buf_attach(bufnr, false, {
      on_lines = function()
        if owners[augroup] ~= token then
          return true
        end
        if not queued then
          queued = true
          vim.schedule(function()
            queued = false
            if owners[augroup] == token then
              schedule_render()
            end
          end)
        end
      end,
    })
  end
  if vim.bo[bufnr].buftype == "terminal" then
    attach_terminal()
  else
    vim.api.nvim_create_autocmd("TermOpen", {
      group = augroup,
      buffer = bufnr,
      once = true,
      callback = attach_terminal,
    })
  end

  vim.api.nvim_create_autocmd("BufWipeout", { group = augroup, buffer = bufnr, callback = function()
    M.stop(augroup)
  end })
  return augroup
end

---@param augroup number The autocmd group id returned by watch()
function M.stop(augroup)
  owners[augroup] = nil
  if cleanup[augroup] then
    cleanup[augroup]()
    cleanup[augroup] = nil
  end
  pcall(vim.api.nvim_del_augroup_by_id, augroup)
end

return M
