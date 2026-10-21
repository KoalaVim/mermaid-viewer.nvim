---@class mermaid_viewer.Size
local M = {}

--- Placeholder grids are limited to 297 rows/columns (size of the diacritics table)
M.MAX_CELLS = 297
--- Terminals reject images larger than this per side
M.MAX_PIXELS = 10000

---@class mermaid_viewer.CellSize
---@field width number
---@field height number

---@param n number
---@return number
local function round(n)
  return math.floor(n + 0.5)
end

--- Inline size: fixed height, width by aspect, shrunk to the text width
---@param aspect number Diagram width / height
---@param height_rows number
---@param text_cols number
---@param cell mermaid_viewer.CellSize
---@return number cols
---@return number rows
function M.inline(aspect, height_rows, text_cols, cell)
  local rows = math.max(1, height_rows)
  local cols = math.max(1, round(rows * cell.height * aspect / cell.width))
  text_cols = math.max(1, text_cols)
  if cols > text_cols then
    cols = text_cols
    rows = math.max(1, round(cols * cell.width / (aspect * cell.height)))
  end
  return cols, rows
end

--- Largest cols/rows with the given aspect that fit in a cols x rows box (fractional)
---@param aspect number
---@param cols number
---@param rows number
---@param cell mermaid_viewer.CellSize
---@return number, number
local function fit(aspect, cols, rows, cell)
  local w, h = cols * cell.width, rows * cell.height
  if w / h > aspect then
    w = h * aspect
  else
    h = w / aspect
  end
  return w / cell.width, h / cell.height
end

--- Highest zoom keeping the larger side within MAX_CELLS
---@param aspect number
---@param cols number Float width in cells
---@param rows number Float height in cells
---@param cell mermaid_viewer.CellSize
---@return number
function M.max_zoom(aspect, cols, rows, cell)
  local c, r = fit(aspect, cols, rows, cell)
  return M.MAX_CELLS / math.max(c, r)
end

--- Float size at a zoom level: fits the float at 1.0x, scaled by zoom, capped at MAX_CELLS per side
---@param aspect number
---@param cols number Float width in cells
---@param rows number Float height in cells
---@param zoom number
---@param cell mermaid_viewer.CellSize
---@return number cols
---@return number rows
function M.float(aspect, cols, rows, zoom, cell)
  local c, r = fit(aspect, cols, rows, cell)
  c, r = c * zoom, r * zoom
  local scale = math.min(1, M.MAX_CELLS / c, M.MAX_CELLS / r)
  c, r = c * scale, r * scale
  return math.min(M.MAX_CELLS, math.max(1, round(c))), math.min(M.MAX_CELLS, math.max(1, round(r)))
end

--- Pixel request for a cols x rows grid, scaled down proportionally to MAX_PIXELS
---@param cols number
---@param rows number
---@param cell mermaid_viewer.CellSize
---@return number width
---@return number height
function M.pixels(cols, rows, cell)
  local w, h = cols * cell.width, rows * cell.height
  local scale = math.min(1, M.MAX_PIXELS / w, M.MAX_PIXELS / h)
  return math.max(1, math.floor(w * scale)), math.max(1, math.floor(h * scale))
end

return M
