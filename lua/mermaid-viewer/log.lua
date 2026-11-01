--- Opt-in file log (config `log = true`) of every sizing decision: editor and cell size, natural render size, the grid
--- computed for it, and the window Neovim actually opened. Open it with :MermaidLog.
---@class mermaid_viewer.Log
local M = {}

local header_written = false

---@return string
function M.path()
  return vim.fs.joinpath(vim.fn.stdpath("log"), "mermaid-viewer.log")
end

---@return boolean
function M.enabled()
  return require("mermaid-viewer.config").options.log == true
end

---@param value any
---@return string
local function fmt(value)
  if type(value) == "table" then
    return vim.inspect(value, { newline = " ", indent = "" })
  end
  return tostring(value)
end

---@param line string
local function append(line)
  local f = io.open(M.path(), "a")
  if f then
    f:write(line, "\n")
    f:close()
  end
end

--- Once per session: what the sizes depend on
local function header()
  header_written = true
  local config = require("mermaid-viewer.config").options
  local v = vim.version()
  append("")
  append(("==== %s nvim %d.%d.%d pid %d"):format(os.date("%Y-%m-%d %H:%M:%S"), v.major, v.minor, v.patch, vim.fn.getpid()))
  append(
    "env "
      .. fmt({
        TERM = vim.env.TERM,
        TERM_PROGRAM = vim.env.TERM_PROGRAM,
        TMUX = vim.env.TMUX and true or nil,
        HERDR = vim.env.HERDR_SESSION or vim.env.HERDR,
        KITTY_WINDOW_ID = vim.env.KITTY_WINDOW_ID,
      })
  )
  append(
    "config "
      .. fmt({
        renderer = config.renderer,
        theme = config.theme,
        float = config.float,
        inline = config.inline,
        zoom_step = config.zoom_step,
        max_zoom = config.max_zoom,
      })
  )
end

--- Log an event with key/value fields; a no-op unless config `log` is on
---@param event string
---@param fields? table
function M.log(event, fields)
  if not M.enabled() then
    return
  end
  if not header_written then
    header()
  end
  local sec, usec = vim.uv.gettimeofday()
  local parts = { os.date("%H:%M:%S", sec) .. ("." .. ("%03d"):format(math.floor(usec / 1000))), event }
  if fields then
    local keys = vim.tbl_keys(fields)
    table.sort(keys)
    for _, k in ipairs(keys) do
      parts[#parts + 1] = k .. "=" .. fmt(fields[k])
    end
  end
  append(table.concat(parts, " "))
end

--- Editor geometry every sizing depends on
---@return table
function M.editor()
  return { columns = vim.o.columns, lines = vim.o.lines, cmdheight = vim.o.cmdheight }
end

return M
