---@class mermaid_viewer.Kitty
local M = {}

local CHUNK_SIZE = 4096
local next_id = 1

---@param params table<string, string|number>
---@param payload? string
---@return string
local function graphics_escape(params, payload)
  local parts = {}
  for k, v in pairs(params) do
    parts[#parts + 1] = k .. "=" .. tostring(v)
  end
  local ctrl = table.concat(parts, ",")
  if payload then
    return "\x1b_G" .. ctrl .. ";" .. payload .. "\x1b\\"
  end
  return "\x1b_G" .. ctrl .. "\x1b\\"
end

--- Write raw bytes to the host terminal.
--- nvim_ui_send (0.12+) goes through the TUI. io.write on the server's non-blocking
--- tty drops whatever doesn't fit in the kernel buffer, truncating image data.
---@param data string
local function send(data)
  if vim.api.nvim_ui_send then
    vim.api.nvim_ui_send(data)
  else
    io.write(data)
    io.flush()
  end
end

---@param png_path string
---@param id number
---@return boolean
function M.transmit(png_path, id)
  local f = io.open(png_path, "rb")
  if not f then
    return false
  end
  local data = f:read("*a")
  f:close()

  local encoded = vim.base64.encode(data)
  local chunks = {}
  for i = 1, #encoded, CHUNK_SIZE do
    chunks[#chunks + 1] = encoded:sub(i, i + CHUNK_SIZE - 1)
  end

  -- Send all chunks in one write; separate writes can be interleaved with TUI output
  local seq = {}
  for i, chunk in ipairs(chunks) do
    local params
    if i == 1 then
      params = {
        a = "t",
        i = id,
        f = 100,
        t = "d",
        q = 2,
        C = 1,
        m = (#chunks > 1) and 1 or 0,
      }
    else
      params = { m = (i < #chunks) and 1 or 0 }
    end
    seq[#seq + 1] = graphics_escape(params, chunk)
  end
  send(table.concat(seq))

  return true
end

---@param id number
---@param row number 1-indexed terminal row
---@param col number 1-indexed terminal column
---@param columns number Display width in terminal cells
---@param rows number Display height in terminal cells
function M.display(id, row, col, columns, rows)
  local seq = "\x1b[?2026h"
    .. "\x1b[s"
    .. "\x1b[" .. row .. ";" .. col .. "H"
    .. graphics_escape({
      a = "p",
      i = id,
      p = id,
      q = 2,
      C = 1,
      z = -1,
      c = columns,
      r = rows,
    })
    .. "\x1b[u"
    .. "\x1b[?2026l"

  send(seq)
end

---@param id number
function M.delete(id)
  send(graphics_escape({ a = "d", d = "i", i = id, q = 2 }))
end

-- Terminals reject larger images (ghostty: 10000px per side)
local MAX_DIMENSION = 10000
local FALLBACK_CELL = { width = 10, height = 20 }

local ffi_ok, ffi = pcall(require, "ffi")
if ffi_ok then
  pcall(ffi.cdef, [[
    struct mermaid_viewer_winsize { unsigned short ws_row, ws_col, ws_xpixel, ws_ypixel; };
    int ioctl(int fd, unsigned long request, ...);
  ]])
end

--- Cell size in pixels, read from the tty via TIOCGWINSZ
---@return { width: number, height: number }
function M.cell_size()
  if not ffi_ok then
    return FALLBACK_CELL
  end
  local TIOCGWINSZ = ffi.os == "OSX" and 0x40087468 or 0x5413
  local ws = ffi.new("struct mermaid_viewer_winsize")
  for _, fd in ipairs({ 1, 2, 0 }) do
    local ok, ret = pcall(ffi.C.ioctl, fd, TIOCGWINSZ, ws)
    if ok and ret == 0 and ws.ws_col > 0 and ws.ws_row > 0 and ws.ws_xpixel > 0 and ws.ws_ypixel > 0 then
      return { width = ws.ws_xpixel / ws.ws_col, height = ws.ws_ypixel / ws.ws_row }
    end
  end
  return FALLBACK_CELL
end

--- Pixel size to render an image filling cols x rows cells, within terminal limits
---@param cols number
---@param rows number
---@param zoom? number
---@return { width: number, height: number }
function M.pixel_size(cols, rows, zoom)
  local cell = M.cell_size()
  local width = cols * cell.width * (zoom or 1)
  local height = rows * cell.height * (zoom or 1)
  local scale = math.min(1, MAX_DIMENSION / width, MAX_DIMENSION / height)
  return { width = math.floor(width * scale), height = math.floor(height * scale) }
end

---@return number
function M.next_id()
  local id = next_id
  next_id = next_id + 1
  return id
end

return M
