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

--- mmdr draws 16px text on lines about this tall; at scale 1.0 one such line takes one cell row
M.NATURAL_LINE_PX = 24

--- Inline size: the natural render scaled to the font, shrunk (keeping the aspect) to fit max_width and max_height
---@param natural { width: number, height: number } Natural render size in pixels
---@param opts { scale: number, max_width: number, max_height: number } <= 1 is a fraction of text_cols / win_rows
---@param text_cols number
---@param win_rows number
---@param cell mermaid_viewer.CellSize
---@return number cols
---@return number rows
function M.inline(natural, opts, text_cols, win_rows, cell)
  local px = cell.height / M.NATURAL_LINE_PX * opts.scale
  local w, h = natural.width * px, natural.height * px
  local max_cols = opts.max_width <= 1 and text_cols * opts.max_width or opts.max_width
  max_cols = math.max(1, math.min(math.floor(max_cols), text_cols, M.MAX_CELLS))
  local max_rows = opts.max_height <= 1 and win_rows * opts.max_height or opts.max_height
  max_rows = math.max(1, math.min(math.floor(max_rows), M.MAX_CELLS))
  local fit = math.min(1, max_cols * cell.width / w, max_rows * cell.height / h)
  local cols = math.max(1, math.min(max_cols, round(w * fit / cell.width)))
  local rows = math.max(1, math.min(max_rows, round(h * fit / cell.height)))
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
