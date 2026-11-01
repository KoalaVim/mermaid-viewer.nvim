---@class mermaid_viewer.Config
local M = {}

---@class mermaid_viewer.InternalConfig
local defaults = {
  ---@type mermaid_viewer.Renderer
  renderer = "mmdr",
  ---@type string
  mmdr_path = "mmdr",
  ---@type { mermaid_js: string|string[]|nil, node_path: string, puppeteer: string|nil, background: string|nil, classic_colors: boolean }
  headless_chrome = {
    mermaid_js = nil,
    node_path = "node",
    puppeteer = nil,
    background = nil,
    classic_colors = true,
  },
  ---@type mermaid_viewer.Theme
  theme = "default",
  ---@type number
  debounce_ms = 300,
  ---@type boolean
  fast_text = false,
  ---@type { width: number, height: number, border: string|string[], mouse: boolean, win_config: vim.api.keyset.win_config }
  float = {
    width = 0.8,
    height = 0.8,
    border = "rounded",
    mouse = true,
    win_config = {},
  },
  ---@type { zoom_in: string, zoom_out: string, zoom_reset: string, close: string[] }
  keys = {
    zoom_in = "i",
    zoom_out = "o",
    zoom_reset = "0",
    close = { "q", "<Esc>" },
  },
  ---@type boolean
  auto_update = true,
  ---@type number
  zoom_step = 1.5,
  ---@type number
  max_zoom = 5.0,
  ---@type number
  pan_step = 1,
  ---@type boolean
  debug = false,
  ---@type { placeholders: boolean|nil }
  terminal = {
    placeholders = nil,
  },
  ---@type string[]
  terminal_filetypes = { "sidekick_terminal" },
  ---@type { enabled: boolean, collapse: boolean, double_click: boolean, scale: number, max_width: number, max_height: number }
  inline = {
    enabled = true,
    collapse = true,
    double_click = true,
    scale = 1.0,
    max_width = 1.0,
    max_height = 40,
  },
}

M.version = "0.1.0"

---@type mermaid_viewer.InternalConfig
M.options = vim.deepcopy(defaults)

local REMOVED_KEYS = { "pan_up", "pan_down", "pan_left", "pan_right" }
local warned_removed = false

--- Drop options removed in favor of native motions, warning once per session
---@param opts table
---@return table opts copy without the removed options
local function drop_removed(opts)
  opts = vim.deepcopy(opts)
  local found = {}
  if type(opts.keys) == "table" then
    for _, key in ipairs(REMOVED_KEYS) do
      if opts.keys[key] ~= nil then
        opts.keys[key] = nil
        table.insert(found, "keys." .. key)
      end
    end
  end
  if type(opts.inline) == "table" and opts.inline.height ~= nil then
    opts.inline.height = nil
    vim.notify(
      "mermaid-viewer: inline.height was removed and is ignored. Diagrams now keep their natural size; "
        .. "use inline.scale, inline.max_height and inline.max_width.",
      vim.log.levels.WARN
    )
  end
  if #found > 0 and not warned_removed then
    warned_removed = true
    vim.notify(
      ("mermaid-viewer: option(s) %s were removed and are ignored. The viewer now uses native motions "
        .. "(h/j/k/l, zh/zl, <C-d>/<C-u>, mouse wheel) to move around."):format(table.concat(found, ", ")),
      vim.log.levels.WARN
    )
  end
  return opts
end

---@param opts? mermaid_viewer.Options
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", defaults, drop_removed(opts or {}))
  M.validate(M.options)
end

---@param cfg mermaid_viewer.InternalConfig
function M.validate(cfg)
  vim.validate({
    renderer = {
      cfg.renderer,
      function(v)
        return v == "mmdr" or v == "headless-chrome"
      end,
      '"mmdr" or "headless-chrome"',
    },
    mmdr_path = { cfg.mmdr_path, "string" },
    headless_chrome = { cfg.headless_chrome, "table" },
    ["headless_chrome.mermaid_js"] = { cfg.headless_chrome.mermaid_js, { "string", "table" }, true },
    ["headless_chrome.node_path"] = { cfg.headless_chrome.node_path, "string" },
    ["headless_chrome.puppeteer"] = { cfg.headless_chrome.puppeteer, "string", true },
    ["headless_chrome.background"] = { cfg.headless_chrome.background, "string", true },
    ["headless_chrome.classic_colors"] = { cfg.headless_chrome.classic_colors, "boolean" },
    theme = { cfg.theme, "string" },
    debounce_ms = { cfg.debounce_ms, "number" },
    fast_text = { cfg.fast_text, "boolean" },
    float = { cfg.float, "table" },
    ["float.mouse"] = { cfg.float.mouse, "boolean" },
    ["float.win_config"] = { cfg.float.win_config, "table" },
    keys = { cfg.keys, "table" },
    auto_update = { cfg.auto_update, "boolean" },
    zoom_step = { cfg.zoom_step, "number" },
    max_zoom = { cfg.max_zoom, "number" },
    pan_step = { cfg.pan_step, "number" },
    debug = { cfg.debug, "boolean" },
    terminal = { cfg.terminal, "table" },
    ["terminal.placeholders"] = { cfg.terminal.placeholders, "boolean", true },
    terminal_filetypes = { cfg.terminal_filetypes, "table" },
    inline = { cfg.inline, "table" },
    ["inline.enabled"] = { cfg.inline.enabled, "boolean" },
    ["inline.collapse"] = { cfg.inline.collapse, "boolean" },
    ["inline.double_click"] = { cfg.inline.double_click, "boolean" },
    ["inline.scale"] = { cfg.inline.scale, "number" },
    ["inline.max_width"] = { cfg.inline.max_width, "number" },
    ["inline.max_height"] = { cfg.inline.max_height, "number" },
  })
end

return M
