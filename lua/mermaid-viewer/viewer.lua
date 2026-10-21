---@class mermaid_viewer.Viewer
local M = {}

local config = require("mermaid-viewer.config")
local cache = require("mermaid-viewer.cache")
local kitty = require("mermaid-viewer.kitty")
local registry = require("mermaid-viewer.registry")
local render = require("mermaid-viewer.render")
local size = require("mermaid-viewer.size")
local source = require("mermaid-viewer.source")

local ns_anchor = vim.api.nvim_create_namespace("mermaid_viewer_viewer_anchor")
local ns_image = vim.api.nvim_create_namespace("mermaid_viewer_viewer_image")

---@param n number
---@return number
local function round(n)
  return math.floor(n + 0.5)
end

---@param n number
---@param lo number
---@param hi number
---@return number
local function clamp(n, lo, hi)
  return math.max(lo, math.min(hi, n))
end

--- Bind to the mermaid block starting at `start_row`; the anchor follows the block across edits above it
---@param buf number
---@param start_row number 0-based row of the opening fence
---@return number mark
function M.anchor(buf, start_row)
  return vim.api.nvim_buf_set_extmark(buf, ns_anchor, start_row, 0, {})
end

---@param src mermaid_viewer.ViewerSource
function M.release_anchor(src)
  if src.mark and vim.api.nvim_buf_is_valid(src.buf) then
    pcall(vim.api.nvim_buf_del_extmark, src.buf, ns_anchor, src.mark)
  end
end

--- Current mermaid text of the bound source. Never looks at any window's cursor.
---@param src mermaid_viewer.ViewerSource
---@return string|nil text
---@return string|nil err
function M.source_text(src)
  if not vim.api.nvim_buf_is_valid(src.buf) then
    return nil, "Source buffer no longer exists"
  end
  if not src.mark then
    return source.extract(src.buf)
  end
  local pos = vim.api.nvim_buf_get_extmark_by_id(src.buf, ns_anchor, src.mark, {})
  if pos[1] then
    for _, block in ipairs(source.blocks(src.buf)) do
      if block.start_row == pos[1] then
        return block.content, nil
      end
    end
  end
  return nil, "Mermaid block no longer exists"
end

--- Largest float content area in cells
---@return number cols
---@return number rows
function M.max_size()
  local float = config.options.float
  return math.max(1, math.floor(vim.o.columns * float.width)), math.max(1, math.floor(vim.o.lines * float.height))
end

---@param aspect number
---@param zoom number
---@return number
local function clamp_zoom(aspect, zoom)
  local cols, rows = M.max_size()
  local cap = math.min(config.options.max_zoom, size.max_zoom(aspect, cols, rows, kitty.cell_size()))
  return math.max(1, math.min(zoom, cap))
end

--- Highest zoom allowed for a diagram (config max_zoom and the 297-cell cap)
---@param aspect number
---@return number
function M.zoom_cap(aspect)
  return clamp_zoom(aspect, math.huge)
end

---@param nw number
---@param nh number
---@return table
local function geometry(nw, nh)
  local border = config.options.float.border
  local extra = (border == nil or border == "none" or border == "") and 0 or 2
  local avail = vim.o.lines - vim.o.cmdheight
  return {
    relative = "editor",
    width = nw,
    height = nh,
    row = math.max(0, math.floor((avail - nh - extra) / 2)),
    col = math.max(0, math.floor((vim.o.columns - nw - extra) / 2)),
  }
end

---@param cols number
---@param rows number
---@return number win
---@return number buf
local function create_window(cols, rows)
  local maxc, maxr = M.max_size()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false

  local win_config = geometry(math.min(cols, maxc), math.min(rows, maxr))
  win_config.style = "minimal"
  win_config.border = config.options.float.border
  local win = vim.api.nvim_open_win(buf, true, win_config)

  local wo = vim.wo[win]
  wo.wrap = false
  wo.number = false
  wo.relativenumber = false
  wo.signcolumn = "no"
  wo.foldcolumn = "0"
  wo.statuscolumn = ""
  wo.cursorline = false
  wo.list = false
  wo.spell = false
  wo.scrolloff = 0
  wo.sidescrolloff = 0
  return win, buf
end

---@param s mermaid_viewer.ViewerState
---@param img mermaid_viewer.Image
---@param cols number
---@param rows number
local function write_grid(s, img, cols, rows)
  local lines = kitty.placeholder_lines(cols, rows)
  vim.bo[s.buf].modifiable = true
  vim.api.nvim_buf_set_lines(s.buf, 0, -1, false, lines)
  vim.bo[s.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(s.buf, ns_image, 0, -1)
  for i, line in ipairs(lines) do
    vim.api.nvim_buf_set_extmark(s.buf, ns_image, i - 1, 0, { end_col = #line, hl_group = img.hl })
  end
end

--- View for a grid of cols x rows shown in a nw x nh window: keeps the cell at `center` (fractions of the grid) in the
--- middle, or top-left when center is nil
---@return vim.fn.winrestview.dict
local function view_for(s, cols, rows, nw, nh, center)
  local leftcol, topline = 0, 1
  if center then
    leftcol = clamp(round(center.x * cols - nw / 2), 0, math.max(0, cols - nw))
    topline = clamp(round(center.y * rows - nh / 2) + 1, 1, math.max(1, rows - nh + 1))
  end
  local lnum = clamp(topline + (center and math.floor(nh / 2) or 0), 1, rows)
  local cell = leftcol + (center and math.floor(nw / 2) or 0)
  local line = vim.api.nvim_buf_get_lines(s.buf, lnum - 1, lnum, false)[1] or ""
  local col = math.max(0, vim.fn.byteidx(line, cell))
  return { topline = topline, leftcol = leftcol, lnum = lnum, col = col, curswant = cell }
end

--- Swap the displayed image. The new image is already acquired (transmitted); the old one is released last.
---@param s mermaid_viewer.ViewerState
---@param img mermaid_viewer.Image
---@param key string
---@param hash string
---@param result mermaid_viewer.DiagramResult
---@param zoom number
---@param opts { reset?: boolean, on_open?: fun(s: mermaid_viewer.ViewerState) }
local function show(s, img, key, hash, result, zoom, opts)
  local cols, rows = result.cols, result.rows
  local maxc, maxr = M.max_size()
  local nw, nh = math.min(cols, maxc), math.min(rows, maxr)
  local old_key = s.key

  local center
  local opened = false
  if not s.win then
    s.win, s.buf = create_window(cols, rows)
    opened = true
  elseif not opts.reset then
    local ow, oh = vim.api.nvim_win_get_width(s.win), vim.api.nvim_win_get_height(s.win)
    local old = vim.api.nvim_win_call(s.win, vim.fn.winsaveview)
    center = { x = (old.leftcol + ow / 2) / s.cols, y = (old.topline - 1 + oh / 2) / s.rows }
  end

  write_grid(s, img, cols, rows)
  if not opened then
    vim.api.nvim_win_set_config(s.win, geometry(nw, nh))
  end
  local view = view_for(s, cols, rows, nw, nh, center)
  vim.api.nvim_win_call(s.win, function()
    vim.fn.winrestview(view)
  end)

  s.image, s.key, s.hash = img, key, hash
  s.aspect, s.cols, s.rows, s.zoom = result.aspect, cols, rows, zoom
  if old_key then
    registry.release(old_key)
  end
  if opened and opts.on_open then
    opts.on_open(s)
  end
end

--- Render the bound source at the requested zoom and swap it into the float (opening the float on first success).
--- Results of superseded requests are dropped.
---@param s mermaid_viewer.ViewerState
---@param opts? { zoom?: number, reset?: boolean, silent?: boolean, on_open?: fun(s: mermaid_viewer.ViewerState), on_missing?: fun(err: string), on_error?: fun(err: string) }
function M.refresh(s, opts)
  opts = opts or {}
  local text, err = M.source_text(s.source)
  if not text then
    if opts.on_missing then
      opts.on_missing(err or "Mermaid source is gone")
    end
    return
  end

  s.gen = s.gen + 1
  local gen = s.gen
  local hash = cache.hash(text)
  local maxc, maxr = M.max_size()
  local cell = kitty.cell_size()
  local zoom = 1.0
  local want = opts.reset and 1.0 or opts.zoom or s.zoom_req

  render.diagram(text, function(aspect)
    zoom = clamp_zoom(aspect, want)
    s.zoom_req = zoom
    return size.float(aspect, maxc, maxr, zoom, cell)
  end, function(render_err, result)
    if s.closed or gen ~= s.gen then
      return
    end
    if render_err or not result then
      if opts.on_error then
        opts.on_error(render_err or "render failed")
      end
      return
    end
    local key = table.concat({ hash, config.options.theme, result.cols .. "x" .. result.rows }, ":")
    local img, acquire_err = registry.acquire(key, result.path, result.cols, result.rows)
    if not img then
      if opts.on_error then
        opts.on_error(acquire_err or "cannot display image")
      end
      return
    end
    show(s, img, key, hash, result, zoom, opts)
  end)
end

--- Keep the view inside the diagram: native scrolling may move past the last column/row
---@param s mermaid_viewer.ViewerState
function M.clamp_view(s)
  if not s.win or not vim.api.nvim_win_is_valid(s.win) then
    return
  end
  local w, h = vim.api.nvim_win_get_width(s.win), vim.api.nvim_win_get_height(s.win)
  vim.api.nvim_win_call(s.win, function()
    local v = vim.fn.winsaveview()
    local left = clamp(v.leftcol, 0, math.max(0, s.cols - w))
    local top = clamp(v.topline, 1, math.max(1, s.rows - h + 1))
    if left ~= v.leftcol or top ~= v.topline then
      vim.fn.winrestview({ leftcol = left, topline = top })
    end
  end)
end

--- Close the float window (the buffer is wiped with it)
---@param s mermaid_viewer.ViewerState
function M.close_window(s)
  if s.win and vim.api.nvim_win_is_valid(s.win) then
    pcall(vim.api.nvim_win_close, s.win, true)
  end
  s.win = nil
end

return M
