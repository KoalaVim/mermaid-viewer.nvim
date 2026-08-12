local M = {}

function M.check()
  vim.health.start("mermaid-viewer")

  if vim.fn.has("nvim-0.10.0") == 1 then
    vim.health.ok("Neovim >= 0.10.0")
  else
    vim.health.error("mermaid-viewer.nvim requires Neovim >= 0.10.0")
  end

  local config = require("mermaid-viewer.config")
  local mmdr = config.options.mmdr_path
  if vim.fn.executable(mmdr) == 1 then
    local result = vim.system({ mmdr, "--version" }, { text = true }):wait()
    local version = vim.trim(result.stdout or "unknown")
    vim.health.ok("mmdr found: " .. version)
  else
    vim.health.error(
      "mmdr not found on PATH",
      { "Install mmdr: cargo install mermaid-rs-renderer", "Or set mmdr_path in setup()" }
    )
  end

  local term = vim.env.TERM or ""
  local term_program = vim.env.TERM_PROGRAM or ""
  local kitty_terms = { "xterm%-kitty", "kitty", "wezterm", "ghostty" }
  local is_kitty = false
  for _, pat in ipairs(kitty_terms) do
    if term:match(pat) or term_program:lower():match(pat) then
      is_kitty = true
      break
    end
  end
  if is_kitty then
    vim.health.ok("Kitty graphics protocol supported (" .. (term_program ~= "" and term_program or term) .. ")")
  else
    vim.health.warn(
      "Terminal may not support Kitty graphics protocol",
      { "Use Kitty, WezTerm, or Ghostty terminal" }
    )
  end

  local valid, err = pcall(config.validate, config.options)
  if valid then
    vim.health.ok("Configuration is valid")
  else
    vim.health.error("Invalid configuration: " .. tostring(err))
  end
end

return M
