--- Inline diagrams: every ```mermaid block of a markdown buffer gets its rendered diagram as virt_lines above the
--- opening fence (Kitty placeholder rows), so it scrolls, clips and folds like buffer text. A mermaid/*.mmd buffer
--- gets its diagram under the last line, and an agent terminal (`terminal_filetypes`) under each diagram it printed.
---@class mermaid_viewer.Inline
local M = {}

local blocks = require("mermaid-viewer.blocks")
local collapse = require("mermaid-viewer.collapse")
local config = require("mermaid-viewer.config")
local kitty = require("mermaid-viewer.kitty")
local registry = require("mermaid-viewer.registry")
local render = require("mermaid-viewer.render")
local size = require("mermaid-viewer.size")
local source = require("mermaid-viewer.source")
local terminal = require("mermaid-viewer.terminal")
local fullscreen = require("mermaid-viewer.fullscreen")

local ns = vim.api.nvim_create_namespace("mermaid_viewer_inline")
-- Same name as blocks.lua's namespace, which resolves to the same id: we read the anchor positions from it
local anchor_ns = vim.api.nvim_create_namespace("mermaid_viewer_blocks")

local RESIZE_DEBOUNCE_MS = 100
local SCROLL_DEBOUNCE_MS = 100

---@class mermaid_viewer.InlineBlock : mermaid_viewer.Block
---@field id number? anchor id (nil until the block was scanned)
---@field hash string

---@class mermaid_viewer.InlineEntry
---@field hash? string content hash of what is displayed (or of the failed render)
---@field text_w? number text width the diagram was sized for
---@field text_h? number window height the diagram was sized for
---@field key? string registry key of the displayed image
---@field err? string error text shown instead of a diagram

---@class mermaid_viewer.InlineState
---@field entries table<number, mermaid_viewer.InlineEntry> anchor id -> displayed result
---@field tokens table<number, number> anchor id -> latest render request, to drop stale callbacks
---@field pending table<number, { hash: string, text_w: number, text_h: number }>
---@field cache? { tick: number, list: mermaid_viewer.InlineBlock[] }
---@field scanning? boolean a scan triggered by update_visible is running
---@field click? boolean the double-click mapping is set
---@field dirty? boolean fullscreen terminal is awaiting reconciliation
---@field reuse mermaid_viewer.InlineEntry[] bounded recently removed fullscreen images
---@field next_token number monotonically increasing render request id

---@type table<number, mermaid_viewer.InlineState>
local states = {}
---@type table<number, boolean> buffers the user switched off; BufWinEnter must not re-enable them
local user_off = {}
local resize_timer

---@param buf number
---@return boolean
function M.is_enabled(buf)
  if buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end
  return states[buf] ~= nil
end

--- The buffer's blocks with their anchor ids. Cached per changedtick; blocks without an anchor yet are not cached,
--- and neither are a terminal's, whose scan follows its windows.
---@param buf number
---@param st mermaid_viewer.InlineState
---@return mermaid_viewer.InlineBlock[]
---@return boolean complete every block has an anchor
local function resolve(buf, st)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  if st.cache and st.cache.tick == tick then
    return st.cache.list
  end
  local by_row = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, anchor_ns, 0, -1, {})) do
    by_row[m[2]] = m[1]
  end
  local list, complete = source.blocks(buf), true
  for _, blk in ipairs(list) do
    blk.id = by_row[blk.start_row]
    blk.hash = vim.fn.sha256(blk.content)
    complete = complete and blk.id ~= nil
  end
  st.cache = complete and source.kind(buf) ~= "terminal" and { tick = tick, list = list } or nil
  return list, complete
end

--- Row the block's virtual lines hang from. Normally the opening fence; a collapsed block's lines are concealed
--- (and virt_lines on a concealed line go with it), so they move to the next visible row, or below the previous
--- visible row when the block ends the buffer.
---@param buf number
---@param blk mermaid_viewer.InlineBlock
---@param hidden boolean
---@return number row
---@return boolean above
local function attach_row(buf, blk, hidden)
  if not hidden then
    if blk.below then
      return blk.end_row, false
    end
    return blk.start_row, true
  end
  local last = vim.api.nvim_buf_line_count(buf) - 1
  local row = blk.end_row + 1
  while row <= last and collapse.hides(buf, row) do
    row = row + 1
  end
  if row <= last then
    return row, true
  end
  row = blk.start_row - 1
  while row >= 0 and collapse.hides(buf, row) do
    row = row - 1
  end
  if row >= 0 then
    return row, false
  end
  return blk.start_row, true
end

---@param msg string
---@param width number
---@return string
local function error_line(msg, width)
  msg = msg:gsub("\27%[[%d;]*m", "")
  local first = ""
  for line in msg:gmatch("[^\r\n]+") do
    if line:match("%S") then
      first = vim.trim(line)
      break
    end
  end
  local text = config.options.renderer .. ": " .. first
  if vim.fn.strdisplaywidth(text) > width then
    while text ~= "" and vim.fn.strdisplaywidth(text) > width - 1 do
      text = vim.fn.strcharpart(text, 0, vim.fn.strchars(text) - 1)
    end
    text = text .. "…"
  end
  return text
end

--- (Re)draw the block's extmark from its entry and collapse state
---@param buf number
---@param st mermaid_viewer.InlineState
---@param blk mermaid_viewer.InlineBlock
local function place(buf, st, blk)
  local e = st.entries[blk.id]
  local hidden = collapse.is_hidden(buf, blk.id)
  local virt = {}
  local img = e and e.key and registry.get(e.key)
  if fullscreen.enabled(buf) then
    pcall(vim.api.nvim_buf_del_extmark, buf, ns, blk.id)
    fullscreen.place(buf, blk, e and e.hash == blk.hash and img or nil)
    return
  end
  if img then
    virt = kitty.placeholder_virt_lines(img.cols, img.rows, img.hl)
  elseif e and e.err and source.kind(buf) ~= "terminal" then
    -- in a terminal the text is the agent's, often still streaming: a failed render just shows nothing
    virt = { { { error_line(e.err, e.text_w or 80), "DiagnosticError" } } }
  end
  if hidden then
    virt[#virt + 1] = { { ("··· %d lines (mermaid)"):format(blk.end_row - blk.start_row + 1), "Comment" } }
  end
  if #virt == 0 then
    pcall(vim.api.nvim_buf_del_extmark, buf, ns, blk.id)
    return
  end
  local row, above = attach_row(buf, blk, hidden)
  vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
    id = blk.id,
    virt_lines = virt,
    virt_lines_above = above,
  })
end

---@param buf number
---@param st mermaid_viewer.InlineState
---@param id number
local function drop_entry(buf, st, id)
  local e = st.entries[id]
  fullscreen.clear(buf, id)
  if e and e.key then
    if fullscreen.enabled(buf) then
      -- Keep a bounded working set alive while a TUI scrolls a diagram out of view and back.
      local cache = st.reuse
      cache[#cache + 1] = e
      if #cache > 16 then
        registry.release(table.remove(cache, 1).key)
      end
    else
      registry.release(e.key)
    end
  end
  st.entries[id] = nil
  st.tokens[id] = nil
  st.pending[id] = nil
  if vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_del_extmark, buf, ns, id)
  end
  collapse.forget(buf, id)
end

--- Collapse conceal marks and all block extmarks, from the current block positions
---@param buf number
function M.refresh(buf)
  local st = states[buf]
  if not st or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local list = resolve(buf, st)
  -- collapse applies to markdown blocks only
  collapse.sync(buf, source.kind(buf) == "markdown" and list or {})
  for _, blk in ipairs(list) do
    if blk.id then
      place(buf, st, blk)
    end
  end
end

---@param buf number
---@param st mermaid_viewer.InlineState
---@param blk mermaid_viewer.InlineBlock
---@param text_w number
---@param text_h number
local function start_render(buf, st, blk, text_w, text_h)
  local id, hash = blk.id, blk.hash
  if fullscreen.enabled(buf) then
    text_h = math.max(1, math.min(text_h, blk.content_end - blk.content_start + 1))
    for i, cached in ipairs(st.reuse) do
      if cached.hash == hash and cached.text_w == text_w and cached.text_h == text_h then
        local old = st.entries[id]
        st.entries[id] = table.remove(st.reuse, i)
        if old and old.key then
          registry.release(old.key)
        end
        place(buf, st, blk)
        return
      end
    end
  end
  st.next_token = st.next_token + 1
  local token = st.next_token
  st.tokens[id] = token
  st.pending[id] = { hash = hash, text_w = text_w, text_h = text_h }

  local function target(aspect, natural)
    local cell = kitty.cell_size()
    local inline_opts = config.options.inline
    if fullscreen.enabled(buf) then
      local max_height = inline_opts.max_height
      if max_height == 0 then
        max_height = text_h
      elseif max_height > 1 then
        max_height = math.min(max_height, text_h)
      end
      inline_opts = vim.tbl_extend("force", inline_opts, { max_height = max_height })
    end
    local cols, rows = size.inline(natural, inline_opts, text_w, text_h, cell)
    require("mermaid-viewer.log").log("inline.size", {
      buf = buf,
      block = id,
      natural = natural,
      aspect = aspect,
      text = { text_w, text_h },
      cell = cell,
      inline = config.options.inline,
      grid = { cols, rows },
    })
    return cols, rows
  end

  render.diagram(blk.content, target, function(err, res)
    if states[buf] ~= st or st.tokens[id] ~= token or not vim.api.nvim_buf_is_valid(buf) then
      require("mermaid-viewer.log").log("inline.cancelled", { buf = buf, block = id, token = token, current_token = st.tokens[id], active = states[buf] == st })
      return
    end
    st.pending[id] = nil
    local current = M.current_block(buf, id)
    if not current or current.hash ~= hash or (fullscreen.enabled(buf) and st.dirty) then
      require("mermaid-viewer.log").log("inline.stale", { buf = buf, block = id, dirty = st.dirty, current = current, hash = hash })
      return
    end
    local e = st.entries[id] or {}
    st.entries[id] = e
    local old_key = e.key

    require("mermaid-viewer.log").log("inline.rendered", {
      buf = buf,
      block = id,
      err = err,
      grid = res and { res.cols, res.rows },
      png_px = res and { res.width_px, res.height_px },
    })
    if err or not res then
      e.err, e.key, e.hash, e.text_w, e.text_h = err or "render failed", nil, hash, text_w, text_h
    else
      local key = table.concat({ hash, config.options.renderer, config.options.theme or "", res.cols .. "x" .. res.rows }, "|")
      -- acquire before releasing the old image, so the swap has no blank frame
      local img = registry.acquire(key, res.path, res.cols, res.rows)
      e.err, e.key, e.hash, e.text_w, e.text_h = nil, img and key or nil, hash, text_w, text_h
    end

    if e.key and config.options.inline.collapse and source.kind(buf) == "markdown" and collapse.auto(buf, id) then
      M.refresh(buf)
    else
      local cur = M.current_block(buf, id)
      if cur then
        place(buf, st, cur)
      end
    end
    if old_key then
      registry.release(old_key)
    end
  end)
end

---@param buf number
---@param id number
---@return mermaid_viewer.InlineBlock?
function M.current_block(buf, id)
  local st = states[buf]
  if not st then
    return nil
  end
  for _, blk in ipairs(resolve(buf, st)) do
    if blk.id == id then
      return blk
    end
  end
end

--- Windows currently showing the buffer, with their visible row range extended by one screen on each side
---@param buf number
---@return { top: number, bot: number }[] ranges 0-based rows
---@return number|nil text_w narrowest text width among the windows
---@return number|nil text_h lowest window height among the windows
local function visible_ranges(buf)
  local ranges, text_w, text_h = {}, nil, nil
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    local info = vim.fn.getwininfo(win)[1]
    local h = vim.api.nvim_win_get_height(win)
    ranges[#ranges + 1] = { top = info.topline - 1 - h, bot = info.topline - 1 + 2 * h }
    local w = info.width - info.textoff
    text_w = text_w and math.min(text_w, w) or w
    text_h = text_h and math.min(text_h, h) or h
  end
  return ranges, text_w, text_h
end

local on_diff

--- Render the blocks that are (nearly) on screen and whose displayed result is stale. Cheap when nothing changed.
---@param buf number
function M.update_visible(buf)
  local st = states[buf]
  if not st or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local ranges, text_w, text_h = visible_ranges(buf)
  if not text_w or #ranges == 0 then
    return
  end
  local list, complete = resolve(buf, st)
  if not complete and not st.scanning and source.kind(buf) == "terminal" then
    -- a terminal scrolled back to diagrams the last scan did not reach: anchor them now
    st.scanning = true
    on_diff(buf, st, blocks.scan(buf))
    st.scanning = nil
    return
  end
  for _, blk in ipairs(list) do
    local visible = false
    for _, r in ipairs(ranges) do
      if blk.start_row <= r.bot and blk.end_row >= r.top then
        visible = true
      end
    end
    local height = fullscreen.enabled(buf) and math.max(1, math.min(text_h, blk.content_end - blk.content_start + 1)) or text_h
    local e, p = st.entries[blk.id or -1], st.pending[blk.id or -1]
    local fresh = e and e.hash == blk.hash and (e.err or (e.text_w == text_w and e.text_h == height))
    local queued = p and p.hash == blk.hash and p.text_w == text_w and p.text_h == height
    if visible and blk.id and not fresh and not queued then
      start_render(buf, st, blk, text_w, height)
    end
  end
end

---@param buf number
---@param st mermaid_viewer.InlineState
---@param diff mermaid_viewer.BlockDiff
on_diff = function(buf, st, diff)
  st.dirty = nil
  st.cache = nil
  for _, blk in ipairs(diff.removed) do
    drop_entry(buf, st, blk.id)
  end
  if fullscreen.enabled(buf) then
    for _, blk in ipairs(diff.changed) do
      drop_entry(buf, st, blk.id)
    end
  end
  M.refresh(buf)
  M.update_visible(buf)
end

--- Block (anchor id) the row belongs to: its lines, its fences, or the row a collapsed block's diagram and marker
--- hang from. Falls back to the untracked scan when inline rendering is off (nil if the block has no anchor).
---@param buf number
---@param row number 0-based
---@return number|nil anchor_id
function M.block_at(buf, row)
  if buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end
  local st = states[buf]
  if not st then
    local blk = blocks.at_row(buf, row)
    return blk and blk.id ~= 0 and blk.id or nil
  end
  local list = resolve(buf, st)
  for _, blk in ipairs(list) do
    if blk.id and row >= blk.start_row and row <= blk.end_row then
      return blk.id
    end
  end
  for _, blk in ipairs(list) do
    if blk.id and collapse.is_hidden(buf, blk.id) then
      local pos = vim.api.nvim_buf_get_extmark_by_id(buf, ns, blk.id, {})
      if pos[1] == row then
        return blk.id
      end
    end
  end
  return nil
end

---@param buf number
---@param row number 0-based
---@param above boolean
---@return { id: number, n: number }[] our extmarks on the row whose virt_lines hang on that side
local function virt_marks(buf, row, above)
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, { row, 0 }, { row, -1 }, { details = true })) do
    local d = m[4]
    if d.virt_lines and (d.virt_lines_above or false) == above then
      out[#out + 1] = { id = m[1], n = #d.virt_lines }
    end
  end
  return out
end

---@param list { id: number, n: number }[]
---@param offset number 1-based virtual line, counted from the text line outwards
---@return number|nil
local function mark_at(list, offset)
  for _, m in ipairs(list) do
    if offset <= m.n then
      return m.id
    end
    offset = offset - m.n
  end
end

--- Block (anchor id) whose inline diagram (or collapse marker) is drawn at the mouse position; nil on buffer text.
--- Neovim reports a click on virtual lines as a click on the text line below them.
---@param pos vim.fn.getmousepos.ret
---@return number|nil anchor_id
function M.diagram_at_mouse(pos)
  if pos.winid == 0 or pos.line == 0 or not vim.api.nvim_win_is_valid(pos.winid) then
    return nil
  end
  local buf = vim.api.nvim_win_get_buf(pos.winid)
  if not states[buf] then
    return nil
  end
  if fullscreen.enabled(buf) then
    return fullscreen.at_mouse(pos)
  end
  local row = pos.line - 1
  local top = vim.fn.screenpos(pos.winid, pos.line, 1).row
  if top == 0 then
    return nil
  end
  if pos.screenrow < top then
    local offset = top - pos.screenrow
    local list = virt_marks(buf, row, true)
    local id = mark_at(list, offset)
    if id or row == 0 then
      return id
    end
    for _, m in ipairs(list) do
      offset = offset - m.n
    end
    -- the previous line's lines below, counted from the bottom up
    local below = virt_marks(buf, row - 1, false)
    local total = 0
    for _, m in ipairs(below) do
      total = total + m.n
    end
    return mark_at(below, total - offset + 1)
  end
  local text = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  local bottom = vim.fn.screenpos(pos.winid, pos.line, math.max(1, #text)).row
  if pos.screenrow > bottom then
    return mark_at(virt_marks(buf, row, false), pos.screenrow - bottom)
  end
  return nil
end

--- Double-click on an inline diagram: open it in the viewer; elsewhere keep the default double-click
---@return string
local function on_double_click()
  local pos = vim.fn.getmousepos()
  local id = M.diagram_at_mouse(pos)
  if not id then
    return "<2-LeftMouse>"
  end
  vim.schedule(function()
    if not vim.api.nvim_win_is_valid(pos.winid) then
      return
    end
    vim.api.nvim_set_current_win(pos.winid)
    local viewer = require("mermaid-viewer")
    if require("mermaid-viewer.state").is_active() then
      viewer.close()
    end
    viewer.view({ block = id })
  end)
  return ""
end

local CLICK_MODES = { "n", "t" }

--- Remove diagrams, markers and collapses from a buffer and release its images; other buffers are unaffected
---@param buf number
local function teardown(buf)
  local st = states[buf]
  if not st then
    return
  end
  states[buf] = nil
  fullscreen.clear(buf)
  for _, e in ipairs(st.reuse) do
    registry.release(e.key)
  end
  for id in pairs(st.entries) do
    local e = st.entries[id]
    if e.key then
      registry.release(e.key)
    end
  end
  collapse.clear(buf)
  blocks.detach(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    if st.click then
      for _, mode in ipairs(CLICK_MODES) do
        pcall(vim.keymap.del, mode, "<2-LeftMouse>", { buffer = buf })
      end
    end
  end
end

---@type table<number, uv_timer_t> terminal buffer -> pending scroll update
local scroll_timers = {}

--- Update a buffer's visible diagrams. A terminal scrolls on every chunk of output, so its update waits until the
--- scrolling pauses.
---@param buf number
local function update_soon(buf)
  if source.kind(buf) ~= "terminal" then
    M.update_visible(buf)
    return
  end
  local t = scroll_timers[buf]
  if t then
    t:stop()
  else
    t = vim.uv.new_timer()
    scroll_timers[buf] = t
  end
  t:start(
    SCROLL_DEBOUNCE_MS,
    0,
    vim.schedule_wrap(function()
      if scroll_timers[buf] == t then
        scroll_timers[buf] = nil
        t:close()
      end
      M.update_visible(buf)
    end)
  )
end

local function update_all_visible()
  for buf in pairs(states) do
    update_soon(buf)
  end
end

local view_ready = false

local function ensure_view_autocmds()
  if view_ready then
    return
  end
  view_ready = true
  local group = vim.api.nvim_create_augroup("MermaidViewerInlineView", { clear = true })
  vim.api.nvim_create_autocmd({ "BufWinEnter", "WinScrolled" }, {
    group = group,
    callback = update_all_visible,
  })
  -- VimResized too, in case a terminal resize leaves every window's size in cells unchanged
  vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
    group = group,
    callback = function()
      if resize_timer then
        resize_timer:stop()
        resize_timer:close()
      end
      resize_timer = vim.uv.new_timer()
      resize_timer:start(
        RESIZE_DEBOUNCE_MS,
        0,
        vim.schedule_wrap(function()
          if resize_timer then
            resize_timer:close()
            resize_timer = nil
          end
          update_all_visible()
        end)
      )
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(ev)
      teardown(ev.buf)
      user_off[ev.buf] = nil
    end,
  })
end

--- Show inline diagrams in a markdown buffer
---@param buf number
---@return boolean enabled
function M.enable(buf)
  if buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end
  if states[buf] then
    return true
  end
  if not vim.api.nvim_buf_is_valid(buf) or not source.kind(buf) then
    return false
  end
  if not terminal.check() then
    return false
  end
  user_off[buf] = nil
  local st = { entries = {}, tokens = {}, pending = {}, reuse = {}, next_token = 0 }
  states[buf] = st
  ensure_view_autocmds()
  if config.options.inline.double_click then
    st.click = true
    vim.keymap.set(CLICK_MODES, "<2-LeftMouse>", on_double_click, {
      buffer = buf,
      expr = true,
      desc = "Open the diagram under the mouse in the mermaid viewer",
    })
  end
  blocks.attach(buf, function(diff)
    if states[buf] == st then
      on_diff(buf, st, diff)
    end
  end, {
    throttle_ms = function()
      return fullscreen.enabled(buf) and 50 or nil
    end,
    notify_unchanged = function()
      return fullscreen.enabled(buf)
    end,
    on_dirty = function()
      if states[buf] == st and fullscreen.enabled(buf) and not st.dirty then
        st.dirty = true
        fullscreen.invalidate(buf)
      end
    end,
  })
  return true
end

---@param buf number
function M.disable(buf)
  if buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end
  user_off[buf] = true
  teardown(buf)
end

---@param buf number
---@return boolean enabled state after toggling
function M.toggle(buf)
  if buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end
  if not source.kind(buf) then
    vim.notify("inline rendering applies to markdown, mermaid and agent terminal buffers only", vim.log.levels.INFO)
    return M.is_enabled(buf)
  end
  if states[buf] then
    M.disable(buf)
    return false
  end
  return M.enable(buf)
end

local function auto_enable(buf)
  if config.options.inline.enabled and not user_off[buf] and source.kind(buf) then
    M.enable(buf)
  end
end

--- Auto-enable inline rendering for markdown, mermaid and agent terminal buffers (when `inline.enabled`) and clean up
--- on exit. Idempotent.
function M.setup()
  local group = vim.api.nvim_create_augroup("MermaidViewerInline", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    callback = function(ev)
      auto_enable(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    callback = function(ev)
      auto_enable(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      for buf in pairs(states) do
        teardown(buf)
      end
      registry.release_all()
    end,
  })
  -- buffers that were already open when the plugin loaded
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    auto_enable(vim.api.nvim_win_get_buf(win))
  end
end

--- Reset module state without touching the terminal (tests)
function M._reset()
  for buf in pairs(states) do
    teardown(buf)
  end
  states, user_off, view_ready = {}, {}, false
  pcall(vim.api.nvim_del_augroup_by_name, "MermaidViewerInline")
  pcall(vim.api.nvim_del_augroup_by_name, "MermaidViewerInlineView")
end

return M
