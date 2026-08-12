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
    io.write(graphics_escape(params, chunk))
  end
  io.flush()

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

  io.write(seq)
  io.flush()
end

---@param id number
function M.delete(id)
  io.write(graphics_escape({ a = "d", d = "i", i = id, q = 2 }))
  io.flush()
end

---@return number
function M.next_id()
  local id = next_id
  next_id = next_id + 1
  return id
end

return M
