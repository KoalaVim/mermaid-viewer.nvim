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

  local ok = pcall(require, "image")
  if ok then
    vim.health.ok("image.nvim is available")
  else
    vim.health.error(
      "image.nvim not found",
      { "Install image.nvim: https://github.com/3rd/image.nvim" }
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
