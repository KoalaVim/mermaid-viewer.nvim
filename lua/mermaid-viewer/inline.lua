--- Inline diagrams: every ```mermaid block of a markdown buffer gets its rendered diagram as virt_lines above the
--- opening fence (Kitty placeholder rows), so it scrolls, clips and folds like buffer text.
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

local ns = vim.api.nvim_create_namespace("mermaid_viewer_inline")
-- Same name as blocks.lua's namespace, which resolves to the same id: we read the anchor positions from it
local anchor_ns = vim.api.nvim_create_namespace("mermaid_viewer_blocks")

local RESIZE_DEBOUNCE_MS = 100

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

--- The buffer's blocks with their anchor ids. Cached per changedtick; blocks without an anchor yet are not cached.
---@param buf number
---@param st mermaid_viewer.InlineState
---@return mermaid_viewer.InlineBlock[]
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
  st.cache = complete and { tick = tick, list = list } or nil
  return list
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
  local text = "mmdr: " .. first
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
  if img then
    virt = kitty.placeholder_virt_lines(img.cols, img.rows, img.hl)
  elseif e and e.err then
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
  if e and e.key then
    registry.release(e.key)
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
  collapse.sync(buf, list)
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
  local token = (st.tokens[id] or 0) + 1
  st.tokens[id] = token
  st.pending[id] = { hash = hash, text_w = text_w, text_h = text_h }

  local function target(_, natural)
    return size.inline(natural, config.options.inline, text_w, text_h, kitty.cell_size())
  end

  render.diagram(blk.content, target, function(err, res)
    if states[buf] ~= st or st.tokens[id] ~= token or not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    st.pending[id] = nil
    local e = st.entries[id] or {}
    st.entries[id] = e
    local old_key = e.key

    if err or not res then
      e.err, e.key, e.hash, e.text_w, e.text_h = err or "render failed", nil, hash, text_w, text_h
    else
      local key = table.concat({ hash, config.options.theme or "", res.cols .. "x" .. res.rows }, "|")
      -- acquire before releasing the old image, so the swap has no blank frame
      local img = registry.acquire(key, res.path, res.cols, res.rows)
      e.err, e.key, e.hash, e.text_w, e.text_h = nil, img and key or nil, hash, text_w, text_h
    end

    local cur = M.current_block(buf, id)
    if cur then
      place(buf, st, cur)
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
  for _, blk in ipairs(resolve(buf, st)) do
    local visible = false
    for _, r in ipairs(ranges) do
      if blk.start_row <= r.bot and blk.end_row >= r.top then
        visible = true
      end
    end
    local e, p = st.entries[blk.id or -1], st.pending[blk.id or -1]
    local fresh = e and e.hash == blk.hash and (e.err or (e.text_w == text_w and e.text_h == text_h))
    local queued = p and p.hash == blk.hash and p.text_w == text_w and p.text_h == text_h
    if visible and blk.id and not fresh and not queued then
      start_render(buf, st, blk, text_w, text_h)
    end
  end
end

---@param buf number
---@param st mermaid_viewer.InlineState
---@param diff mermaid_viewer.BlockDiff
local function on_diff(buf, st, diff)
  st.cache = nil
  for _, blk in ipairs(diff.removed) do
    drop_entry(buf, st, blk.id)
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

--- Remove diagrams, markers and collapses from a buffer and release its images; other buffers are unaffected
---@param buf number
local function teardown(buf)
  local st = states[buf]
  if not st then
    return
  end
  states[buf] = nil
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
  end
end

local function update_all_visible()
  for buf in pairs(states) do
    M.update_visible(buf)
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
  vim.api.nvim_create_autocmd("WinResized", {
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
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= "markdown" then
    return false
  end
  if not terminal.check() then
    return false
  end
  user_off[buf] = nil
  local st = { entries = {}, tokens = {}, pending = {} }
  states[buf] = st
  ensure_view_autocmds()
  blocks.attach(buf, function(diff)
    if states[buf] == st then
      on_diff(buf, st, diff)
    end
  end)
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
  if vim.bo[buf].filetype ~= "markdown" then
    vim.notify("inline rendering applies to markdown buffers only", vim.log.levels.INFO)
    return M.is_enabled(buf)
  end
  if states[buf] then
    M.disable(buf)
    return false
  end
  return M.enable(buf)
end

local function auto_enable(buf)
  if config.options.inline.enabled and not user_off[buf] and vim.bo[buf].filetype == "markdown" then
    M.enable(buf)
  end
end

--- Auto-enable inline rendering for markdown buffers (when `inline.enabled`) and clean up on exit. Idempotent.
function M.setup()
  local group = vim.api.nvim_create_augroup("MermaidViewerInline", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "markdown",
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
