---@class mermaid_viewer.Viewer
local M = {}

local config = require("mermaid-viewer.config")

---@type number|nil
local win = nil
---@type number|nil
local buf = nil

--- Open a floating window for the viewer. Returns win and buf handles.
--- If already open, returns existing handles.
---@return number win Window handle
---@return number buf Buffer handle
function M.open()
  if M.is_open() then
    return win, buf
  end

  local float = config.options.float

  local width = math.floor(vim.o.columns * float.width)
  local height = math.floor(vim.o.lines * float.height)
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"

  win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = float.border,
  })

  vim.bo[buf].modifiable = false
  vim.bo[buf].buftype = "nofile"

  return win, buf
end

--- Close the viewer float window and wipe the buffer
function M.close()
  if win ~= nil and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
  win = nil
  buf = nil
end

--- Check if the viewer float is currently open and valid
---@return boolean
function M.is_open()
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

--- Get the current float dimensions in cells
---@return { width: number, height: number }|nil
function M.get_dimensions()
  if not M.is_open() then
    return nil
  end

  return {
    width = vim.api.nvim_win_get_width(win),
    height = vim.api.nvim_win_get_height(win),
  }
end

return M
