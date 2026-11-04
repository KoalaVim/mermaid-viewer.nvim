local M = {}

function M.check()
  vim.health.start("mermaid-viewer")

  if vim.fn.has("nvim-0.12") == 1 then
    vim.health.ok("Neovim >= 0.12")
  else
    vim.health.error("mermaid-viewer.nvim requires Neovim >= 0.12", { "Upgrade Neovim to 0.12 or newer" })
  end

  local config = require("mermaid-viewer.config")
  if config.options.renderer == "headless-chrome" then
    M.check_headless_chrome()
  else
    M.check_mmdr()
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
        { "Use a supported terminal: Kitty, Ghostty, herdr, Rex", "Or force it with terminal.placeholders = true in setup()" }
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

function M.check_mmdr()
  local mmdr = require("mermaid-viewer.config").options.mmdr_path
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
end

function M.check_headless_chrome()
  local config = require("mermaid-viewer.config")
  local hc = require("mermaid-viewer.headless_chrome")
  vim.health.ok('renderer = "headless-chrome"')

  local node = config.options.headless_chrome.node_path
  if vim.fn.executable(node) == 1 then
    local result = vim.system({ node, "--version" }, { text = true }):wait()
    vim.health.ok("node found: " .. vim.trim(result.stdout or "unknown"))
  else
    vim.health.error("node not found: " .. node, { "Install Node.js", "Or set headless_chrome.node_path in setup()" })
  end

  local js, err = hc.mermaid_js()
  if js then
    for i, path in ipairs(js) do
      vim.health.ok((i == 1 and "mermaid.js: " or "mermaid.js fallback: ") .. path)
    end
  else
    vim.health.error(err, { "npm install -g @mermaid-js/mermaid-cli", "Or set headless_chrome.mermaid_js in setup()" })
  end

  local pdir = hc.puppeteer_dir()
  if pdir then
    vim.health.ok("puppeteer resolved from: " .. pdir)
  else
    vim.health.warn("no puppeteer location found; relying on node's own module resolution", {
      "Install mermaid-cli (ships puppeteer): npm install -g @mermaid-js/mermaid-cli",
      "Or set headless_chrome.puppeteer to a directory containing node_modules/puppeteer",
    })
  end
end

return M
