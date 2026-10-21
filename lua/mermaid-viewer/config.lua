---@class mermaid_viewer.Config
local M = {}

---@class mermaid_viewer.InternalConfig
local defaults = {
  ---@type string
  mmdr_path = "mmdr",
  ---@type mermaid_viewer.Theme
  theme = "default",
  ---@type number
  debounce_ms = 300,
  ---@type boolean
  fast_text = false,
  ---@type { width: number, height: number, border: string|string[] }
  float = {
    width = 0.8,
    height = 0.8,
    border = "rounded",
  },
  ---@type { zoom_in: string, zoom_out: string, zoom_reset: string, close: string[] }
  keys = {
    zoom_in = "+",
    zoom_out = "-",
    zoom_reset = "0",
    close = { "q", "<Esc>" },
  },
  ---@type boolean
  auto_update = true,
  ---@type number
  zoom_step = 1.5,
  ---@type number
  max_zoom = 5.0,
  ---@type boolean
  debug = false,
  ---@type { placeholders: boolean|nil }
  terminal = {
    placeholders = nil,
  },
  ---@type { enabled: boolean, height: number }
  inline = {
    enabled = true,
    height = 15,
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
  if opts.pan_step ~= nil then
    opts.pan_step = nil
    table.insert(found, "pan_step")
  end
  if type(opts.keys) == "table" then
    for _, key in ipairs(REMOVED_KEYS) do
      if opts.keys[key] ~= nil then
        opts.keys[key] = nil
        table.insert(found, "keys." .. key)
      end
    end
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
    mmdr_path = { cfg.mmdr_path, "string" },
    theme = { cfg.theme, "string" },
    debounce_ms = { cfg.debounce_ms, "number" },
    fast_text = { cfg.fast_text, "boolean" },
    float = { cfg.float, "table" },
    keys = { cfg.keys, "table" },
    auto_update = { cfg.auto_update, "boolean" },
    zoom_step = { cfg.zoom_step, "number" },
    max_zoom = { cfg.max_zoom, "number" },
    debug = { cfg.debug, "boolean" },
    terminal = { cfg.terminal, "table" },
    ["terminal.placeholders"] = { cfg.terminal.placeholders, "boolean", true },
    inline = { cfg.inline, "table" },
    ["inline.enabled"] = { cfg.inline.enabled, "boolean" },
    ["inline.height"] = { cfg.inline.height, "number" },
  })
end

return M
