---@class mermaid_viewer.Viewer
local M = {}

local config = require("mermaid-viewer.config")
local log = require("mermaid-viewer.log")
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

--- Cells the float's border adds on each axis
---@return number
local function border_cells()
  local float = config.options.float
  local border = (float.win_config or {}).border or float.border
  return (border == nil or border == "none" or border == "") and 0 or 2
end

--- Rows and columns a float (with its border) can use: the editor minus the command line
---@return number cols
---@return number rows
local function available()
  local extra = border_cells()
  return vim.o.columns - extra, vim.o.lines - vim.o.cmdheight - extra
end

--- Largest float content area in cells: the configured fraction of the editor (or win_config's width/height), never
--- more than fits on screen with the border, so the diagram grid always matches the window Neovim actually opens
---@return number cols
---@return number rows
function M.max_size()
  local float = config.options.float
  local user = float.win_config or {}
  local avail_cols, avail_rows = available()
  local cols = math.min(user.width or math.floor(vim.o.columns * float.width), avail_cols)
  local rows = math.min(user.height or math.floor(vim.o.lines * float.height), avail_rows)
  cols, rows = math.max(1, cols), math.max(1, rows)
  log.log("viewer.max_size", {
    editor = log.editor(),
    float = { width = float.width, height = float.height, border = float.border, win_config = user },
    border_cells = border_cells(),
    available = { avail_cols, avail_rows },
    max = { cols, rows },
  })
  return cols, rows
end

---@param aspect number
---@param zoom number
---@return number
local function clamp_zoom(aspect, zoom)
  local cols, rows = M.max_size()
  local cell, fit = kitty.cell_size(), config.options.float.fit
  local cap = math.min(config.options.max_zoom, size.max_zoom(aspect, cols, rows, cell, fit))
  local floor = math.min(config.options.min_zoom, size.whole_zoom(aspect, cols, rows, cell, fit))
  return math.max(floor, math.min(zoom, math.max(cap, floor)))
end

--- Lowest zoom allowed for a diagram: config min_zoom, or lower when that still doesn't show the whole diagram
---@param aspect number
---@return number
function M.zoom_floor(aspect)
  return clamp_zoom(aspect, 0)
end

--- Highest zoom allowed for a diagram (config max_zoom and the 297-cell cap)
---@param aspect number
---@return number
function M.zoom_cap(aspect)
  return clamp_zoom(aspect, math.huge)
end

--- Centered float config for a nw x nh window, with the user's float.win_config merged over it
---@param nw number
---@param nh number
---@return vim.api.keyset.win_config
local function geometry(nw, nh)
  local float = config.options.float
  local user = float.win_config or {}
  local extra = border_cells()
  local avail = vim.o.lines - vim.o.cmdheight
  return vim.tbl_extend("force", {
    relative = "editor",
    width = nw,
    height = nh,
    row = math.max(0, math.floor((avail - nh - extra) / 2)),
    col = math.max(0, math.floor((vim.o.columns - nw - extra) / 2)),
    style = "minimal",
    border = float.border,
  }, user)
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
  local win = vim.api.nvim_open_win(buf, true, win_config)
  log.log("viewer.open_win", {
    asked = { win_config.width, win_config.height, row = win_config.row, col = win_config.col, border = win_config.border },
    got = { vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_height(win) },
    editor = log.editor(),
  })

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

--- View for a grid of cols x rows shown in a nw x nh window: puts the point at `center` (fractions of the grid) at the
--- window offset (ox, oy) (default: the middle), or the top-left when center is nil
---@param center? { x: number, y: number, ox?: number, oy?: number }
---@return vim.fn.winrestview.dict
local function view_for(s, cols, rows, nw, nh, center)
  local leftcol, topline, ox, oy = 0, 1, 0, 0
  if center then
    ox, oy = center.ox or nw / 2, center.oy or nh / 2
    leftcol = clamp(round(center.x * cols - ox), 0, math.max(0, cols - nw))
    topline = clamp(round(center.y * rows - oy) + 1, 1, math.max(1, rows - nh + 1))
  end
  local lnum = clamp(topline + math.floor(oy), 1, rows)
  local cell = math.min(leftcol + math.floor(ox), cols - 1)
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
---@param opts { reset?: boolean, focus?: mermaid_viewer.Focus, on_open?: fun(s: mermaid_viewer.ViewerState) }
local function show(s, img, key, hash, result, zoom, opts)
  local cols, rows = result.cols, result.rows
  if img.cols ~= cols or img.rows ~= rows then
    kitty.place_virtual(img.id, cols, rows)
    img.cols, img.rows = cols, rows
  end
  local maxc, maxr = M.max_size()
  local nw, nh = math.min(cols, maxc), math.min(rows, maxr)
  local old_key = s.key

  local center
  local opened = false
  if not s.win then
    s.win, s.buf = create_window(cols, rows)
    opened = true
  elseif opts.focus then
    -- keep the grid cell under the pointer under the pointer
    local f = opts.focus
    center = {
      x = (f.gx + 0.5) / s.cols,
      y = (f.gy + 0.5) / s.rows,
      ox = clamp(f.ox + 0.5, 0.5, nw - 0.5),
      oy = clamp(f.oy + 0.5, 0.5, nh - 0.5),
    }
  elseif not opts.reset then
    local ow, oh = vim.api.nvim_win_get_width(s.win), vim.api.nvim_win_get_height(s.win)
    local old = vim.api.nvim_win_call(s.win, vim.fn.winsaveview)
    center = { x = (old.leftcol + ow / 2) / s.cols, y = (old.topline - 1 + oh / 2) / s.rows }
  end

  write_grid(s, img, cols, rows)
  if not opened then
    local win_config = geometry(nw, nh)
    win_config.noautocmd = nil -- only valid when opening
    vim.api.nvim_win_set_config(s.win, win_config)
  end
  local view = view_for(s, cols, rows, nw, nh, center)
  vim.api.nvim_win_call(s.win, function()
    vim.fn.winrestview(view)
  end)
  if log.enabled() then
    local wc = vim.api.nvim_win_get_config(s.win)
    log.log("viewer.show", {
      grid = { cols, rows },
      planned_win = { nw, nh },
      win = { vim.api.nvim_win_get_width(s.win), vim.api.nvim_win_get_height(s.win), row = wc.row, col = wc.col },
      winbar = vim.wo[s.win].winbar ~= "" and vim.wo[s.win].winbar or nil,
      zoom = zoom,
      aspect = result.aspect,
      image = { id = img.id, cols = img.cols, rows = img.rows },
      png_px = result.width_px and { result.width_px, result.height_px } or nil,
      view = { topline = view.topline, leftcol = view.leftcol },
      opened = opened,
      editor = log.editor(),
    })
  end

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
---@param opts? { zoom?: number, reset?: boolean, focus?: mermaid_viewer.Focus, silent?: boolean, rerender?: boolean, on_open?: fun(s: mermaid_viewer.ViewerState), on_missing?: fun(err: string), on_error?: fun(err: string) }
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

  -- Zoom only: the image already holds the max-zoom resolution, so resize its placement instead of re-rendering
  if not opts.rerender and s.image and s.hash == hash and s.theme == config.options.theme and s.win then
    s.gen = s.gen + 1
    zoom = clamp_zoom(s.aspect, want)
    s.zoom_req = zoom
    local cols, rows = size.float(s.aspect, maxc, maxr, zoom, cell, config.options.float.fit)
    local key = s.key
    s.key = nil -- keep the single reference: show releases the previous key
    show(s, s.image, key, hash, { aspect = s.aspect, cols = cols, rows = rows }, zoom, opts)
    return
  end

  log.log("viewer.refresh", {
    want_zoom = want,
    rerender = opts.rerender,
    reset = opts.reset,
    max = { maxc, maxr },
    cell = cell,
  })
  -- Render once at the max-zoom grid (capped by size.pixels); every zoom level shows that image scaled
  local display
  render.diagram(text, function(aspect)
    zoom = clamp_zoom(aspect, want)
    s.zoom_req = zoom
    display = { size.float(aspect, maxc, maxr, zoom, cell, config.options.float.fit) }
    return size.float(aspect, maxc, maxr, clamp_zoom(aspect, math.huge), cell, config.options.float.fit)
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
    log.log("viewer.rendered", {
      aspect = result.aspect,
      natural = require("mermaid-viewer.cache").get_natural(hash),
      render_grid = { result.cols, result.rows },
      png_px = { result.width_px, result.height_px },
      display_grid = display,
      zoom = zoom,
    })
    local key = table.concat({ hash, config.options.theme, result.cols .. "x" .. result.rows }, ":")
    local img, acquire_err = registry.acquire(key, result.path, display[1], display[2])
    if not img then
      if opts.on_error then
        opts.on_error(acquire_err or "cannot display image")
      end
      return
    end
    s.theme = config.options.theme
    show(s, img, key, hash, { aspect = result.aspect, cols = display[1], rows = display[2] }, zoom, opts)
  end)
end

--- Fit the float to a resized editor: re-place the current image at once (window size, position, zoom cap), then
--- re-render at the new size so the resolution matches (a cache hit when the max float size did not change)
---@param s mermaid_viewer.ViewerState
function M.resized(s)
  if s.closed or not s.win or not vim.api.nvim_win_is_valid(s.win) then
    return
  end
  log.log("viewer.resized", { editor = log.editor(), zoom = s.zoom_req })
  M.refresh(s, { zoom = s.zoom_req })
  M.refresh(s, { zoom = s.zoom_req, rerender = true })
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

--- Show the grid from column `left` and row `top` (0-based), stopping at the diagram's edges. The cursor goes to the
--- middle of the new view, so later native motions start from there.
---@param s mermaid_viewer.ViewerState
---@param left number
---@param top number
function M.pan_to(s, left, top)
  if not s.win or not vim.api.nvim_win_is_valid(s.win) then
    return
  end
  local w, h = vim.api.nvim_win_get_width(s.win), vim.api.nvim_win_get_height(s.win)
  vim.api.nvim_win_call(s.win, function()
    left = clamp(left, 0, math.max(0, s.cols - w))
    top = clamp(top + 1, 1, math.max(1, s.rows - h + 1))
    local lnum = clamp(top + math.floor(h / 2), 1, s.rows)
    local cell = math.min(left + math.floor(w / 2), s.cols - 1)
    local line = vim.api.nvim_buf_get_lines(s.buf, lnum - 1, lnum, false)[1] or ""
    local col = math.max(0, vim.fn.byteidx(line, cell))
    vim.fn.winrestview({ topline = top, leftcol = left, lnum = lnum, col = col, curswant = cell })
  end)
end

--- Move the view by dx columns and dy rows (see pan_to)
---@param s mermaid_viewer.ViewerState
---@param dx number
---@param dy number
function M.pan(s, dx, dy)
  if not s.win or not vim.api.nvim_win_is_valid(s.win) then
    return
  end
  local v = vim.api.nvim_win_call(s.win, vim.fn.winsaveview)
  M.pan_to(s, v.leftcol + dx, v.topline - 1 + dy)
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
