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
  ---@type { zoom_in: string, zoom_out: string, zoom_reset: string, pan_up: string, pan_down: string, pan_left: string, pan_right: string, close: string[] }
  keys = {
    zoom_in = "+",
    zoom_out = "-",
    zoom_reset = "0",
    pan_up = "k",
    pan_down = "j",
    pan_left = "h",
    pan_right = "l",
    close = { "q", "<Esc>" },
  },
  ---@type boolean
  auto_update = true,
  ---@type number
  zoom_step = 1.5,
  ---@type number
  max_zoom = 5.0,
  ---@type number
  pan_step = 5,
}

M.version = "0.1.0"

---@type mermaid_viewer.InternalConfig
M.options = vim.deepcopy(defaults)

---@param opts? mermaid_viewer.Options
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", defaults, opts or {})
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
    pan_step = { cfg.pan_step, "number" },
  })
end

return M
