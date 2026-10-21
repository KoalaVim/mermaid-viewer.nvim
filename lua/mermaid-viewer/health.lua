local M = {}

function M.check()
  vim.health.start("mermaid-viewer")

  if vim.fn.has("nvim-0.12") == 1 then
    vim.health.ok("Neovim >= 0.12")
  else
    vim.health.error("mermaid-viewer.nvim requires Neovim >= 0.12", { "Upgrade Neovim to 0.12 or newer" })
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

  -- supported() folds termguicolors into its answer; report it on its own so the terminal verdict stays accurate
  if vim.o.termguicolors then
    vim.health.ok("'termguicolors' is enabled")
    local supported, reason = require("mermaid-viewer.terminal").supported()
    if supported then
      vim.health.ok("Kitty graphics Unicode placeholders supported (" .. reason .. ")")
    else
      vim.health.error(
        "Terminal does not support Kitty graphics Unicode placeholders: " .. reason,
        { "Use a supported terminal: Kitty, Ghostty, herdr", "Or force it with terminal.placeholders = true in setup()" }
      )
    end
  else
    vim.health.error(
      "'termguicolors' is off; placeholders encode image ids in colors",
      { "Set vim.o.termguicolors = true" }
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
