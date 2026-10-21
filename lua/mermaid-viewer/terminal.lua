---@class mermaid_viewer.Terminal
local M = {}

-- TERM_PROGRAM values known to support Kitty Unicode placeholders.
local TERM_PROGRAMS = {
  kitty = true,
  ghostty = true,
  -- PROVISIONAL: herdr is assumed to work until the manual spike (task 1.1) says otherwise. Flip to false if not.
  herdr = true,
}

local TERMS = { ["xterm-kitty"] = true, ["xterm-ghostty"] = true }
local ENV_MARKERS = { "KITTY_WINDOW_ID", "GHOSTTY_RESOURCES_DIR" }

local SUPPORTED_NAMES = "Kitty, Ghostty, herdr"

local warned = false
local debug_group

---@return boolean supported
---@return string reason
function M.supported()
  if vim.o.termguicolors == false then
    return false, "'termguicolors' is off (image ids are encoded in highlight colors)"
  end

  local override = require("mermaid-viewer.config").options.terminal.placeholders
  if override == true then
    return true, "forced on by config (terminal.placeholders)"
  elseif override == false then
    return false, "disabled by config (terminal.placeholders)"
  end

  local program = vim.env.TERM_PROGRAM
  if program and program ~= "" then
    -- Decisive when set: inside tmux/WezTerm leftovers like KITTY_WINDOW_ID must not count
    if TERM_PROGRAMS[program:lower()] then
      return true, "TERM_PROGRAM=" .. program
    end
    return false, "unsupported terminal (TERM_PROGRAM=" .. program .. ")"
  end
  if TERMS[vim.env.TERM or ""] then
    return true, "TERM=" .. vim.env.TERM
  end
  for _, name in ipairs(ENV_MARKERS) do
    if vim.env[name] and vim.env[name] ~= "" then
      return true, name .. " is set"
    end
  end
  return false, "unsupported terminal (TERM=" .. tostring(vim.env.TERM) .. ")"
end

--- Notify once per session that diagrams can't be displayed
function M.warn_once()
  if warned then
    return
  end
  warned = true
  local _, reason = M.supported()
  vim.notify(
    ("mermaid-viewer: diagrams cannot be displayed: %s. Supported terminals: %s (Kitty Unicode placeholders). "
      .. "Set `terminal = { placeholders = true }` to force."):format(reason, SUPPORTED_NAMES),
    vim.log.levels.WARN
  )
end

--- Gate for graphics output: true if supported, otherwise warns once and returns false
---@return boolean
function M.check()
  if M.supported() then
    return true
  end
  M.warn_once()
  return false
end

---@type string[] terminal graphics replies received in debug mode (ESC_G ...)
M.responses = {}

--- Debug mode: log kitty graphics replies (delivered via TermResponse) with vim.notify at DEBUG level and
--- keep them in `M.responses`. Idempotent; cheap when debug is off.
function M.attach_debug()
  if debug_group then
    return
  end
  debug_group = vim.api.nvim_create_augroup("MermaidViewerTermDebug", { clear = true })
  vim.api.nvim_create_autocmd("TermResponse", {
    group = debug_group,
    callback = function(ev)
      local seq = ev.data and ev.data.sequence
      if not require("mermaid-viewer.config").options.debug or type(seq) ~= "string" then
        return
      end
      if seq:sub(1, 3) ~= "\27_G" then
        return
      end
      local msg = seq:sub(4):gsub("\27\\$", "")
      M.responses[#M.responses + 1] = msg
      vim.notify("mermaid-viewer: terminal reply: " .. msg, vim.log.levels.DEBUG)
    end,
  })
end

--- Reset module state (tests)
function M._reset()
  warned = false
  M.responses = {}
  if debug_group then
    pcall(vim.api.nvim_del_augroup_by_id, debug_group)
    debug_group = nil
  end
end

return M
