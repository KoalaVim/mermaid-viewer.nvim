--- "headless-chrome" renderer: renders with mermaid.js in headless Chrome (via puppeteer), using the current mermaid
--- shipped with mermaid-cli (behind `mmdc`) unless headless_chrome.mermaid_js says otherwise.
---@class mermaid_viewer.HeadlessChrome
local M = {}

local config = require("mermaid-viewer.config")

local MERMAID_DIST = "mermaid/dist/mermaid.min.js"

---@return string script path of the node render script shipped with this plugin
function M.script()
  local src = debug.getinfo(1, "S").source:sub(2)
  return vim.fs.joinpath(vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(src))), "scripts", "headless-chrome-render.mjs")
end

--- Package root of the mermaid-cli install behind `mmdc`
---@return string|nil
local function mmdc_dir()
  local mmdc = vim.fn.exepath("mmdc")
  if mmdc == "" then
    return nil
  end
  -- <prefix>/lib/node_modules/@mermaid-js/mermaid-cli/src/cli.js -> package root
  local real = vim.uv.fs_realpath(mmdc) or mmdc
  for dir in vim.fs.parents(real) do
    if vim.uv.fs_stat(vim.fs.joinpath(dir, "package.json")) then
      return dir
    end
  end
end

--- mermaid-cli's mermaid.min.js: in its own node_modules, or hoisted next to it
---@return string|nil
local function mmdc_mermaid_js()
  local dir = mmdc_dir()
  if not dir then
    return nil
  end
  for parent in vim.fs.parents(vim.fs.joinpath(dir, "x")) do
    local path = vim.fs.joinpath(parent, "node_modules", MERMAID_DIST)
    if vim.uv.fs_stat(path) then
      return path
    end
  end
end

--- mermaid.min.js files to try in order: the option (a path or list of paths), else mermaid-cli's
---@return string[]|nil paths, string|nil err
function M.mermaid_js()
  local opt = config.options.headless_chrome.mermaid_js
  if opt then
    local paths = {}
    for _, path in ipairs(type(opt) == "table" and opt or { opt }) do
      path = vim.fs.normalize(path)
      if not vim.uv.fs_stat(path) then
        return nil, "mermaid.js not found at " .. path
      end
      table.insert(paths, path)
    end
    if #paths == 0 then
      return nil, "headless_chrome.mermaid_js is empty"
    end
    return paths
  end

  local path = mmdc_mermaid_js()
  if not path then
    return nil, "mermaid-cli's mermaid.js not found: npm install -g @mermaid-js/mermaid-cli (or set headless_chrome.mermaid_js)"
  end
  return { vim.fs.normalize(path) }
end

--- Directory to resolve puppeteer from: the option, else the mermaid-cli install behind `mmdc` (which ships it)
---@return string|nil
function M.puppeteer_dir()
  local dir = config.options.headless_chrome.puppeteer
  if dir then
    return vim.fs.normalize(dir)
  end
  return mmdc_dir()
end

--- markdown-preview.nvim's extra mermaid config: the `maid` key of g:mkdp_preview_options
---@return table|nil
function M.maid()
  local opts = vim.g.mkdp_preview_options
  if type(opts) == "table" and type(opts.maid) == "table" and next(opts.maid) then
    return opts.maid
  end
end

--- Command rendering input_path to output_path
---@param input_path string
---@param output_path string
---@param width number|nil
---@param height number|nil
---@return string[]|nil cmd, string|nil err
function M.cmd(input_path, output_path, width, height)
  local mermaid_js, err = M.mermaid_js()
  if not mermaid_js then
    return nil, err
  end
  local opt = config.options
  local mp = opt.headless_chrome
  local cmd = { mp.node_path, M.script(), "-i", input_path, "-o", output_path }
  for _, js in ipairs(mermaid_js) do
    vim.list_extend(cmd, { "--mermaid", js })
  end
  local pdir = M.puppeteer_dir()
  if pdir then
    vim.list_extend(cmd, { "--puppeteer", pdir })
  end
  if width and height then
    vim.list_extend(cmd, { "--width", tostring(width), "--height", tostring(height) })
  end
  if opt.theme then
    vim.list_extend(cmd, { "--theme", opt.theme })
  end
  local maid = M.maid()
  if maid then
    vim.list_extend(cmd, { "--config", vim.json.encode(maid) })
  end
  if mp.background then
    vim.list_extend(cmd, { "--background", mp.background })
  end
  if mp.classic_colors then
    vim.list_extend(cmd, { "--classic-colors", "true" })
  end
  return cmd
end

return M
