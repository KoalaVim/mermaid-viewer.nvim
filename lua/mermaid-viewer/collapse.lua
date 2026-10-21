--- Collapse mermaid blocks: the block's lines (fences included) are hidden with an extmark `conceal_lines`, and the
--- inline module draws the `··· N lines (mermaid)` marker below the diagram. This module owns the state and the
--- conceal extmarks; inline.lua decides where the diagram and marker hang (see inline.attach_row).
---@class mermaid_viewer.Collapse
local M = {}

local ns = vim.api.nvim_create_namespace("mermaid_viewer_collapse")

---@class mermaid_viewer.CollapseState
---@field collapsed table<number, boolean> anchor id -> user wants it collapsed
---@field expanded table<number, boolean> anchor id -> expanded temporarily for editing
---@field marks table<number, number> anchor id -> conceal extmark id
---@field saved table<number, { conceallevel?: number, concealcursor?: string }> window -> options to restore

---@type table<number, mermaid_viewer.CollapseState>
local states = {}

local EDIT_MODES = "[iRvVsS\22\19]"

---@param buf number
---@return mermaid_viewer.CollapseState
local function state_for(buf)
  if not states[buf] then
    states[buf] = { collapsed = {}, expanded = {}, marks = {}, saved = {} }
  end
  return states[buf]
end

---@param buf number
---@param id number
---@return boolean
function M.is_collapsed(buf, id)
  local st = states[buf]
  return st ~= nil and st.collapsed[id] == true
end

--- Whether the block's lines are hidden right now (collapsed and not temporarily expanded)
---@param buf number
---@param id number
---@return boolean
function M.is_hidden(buf, id)
  local st = states[buf]
  return st ~= nil and st.collapsed[id] == true and not st.expanded[id]
end

--- Whether `row` lies inside a currently hidden range
---@param buf number
---@param row number 0-based
---@return boolean
function M.hides(buf, row)
  if not states[buf] then
    return false
  end
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, { row, 0 }, { row, -1 }, { overlap = true, details = true })
  for _, m in ipairs(marks) do
    if m[4].conceal_lines and (m[4].end_row or m[2]) >= row then
      return true
    end
  end
  return false
end

---@param st mermaid_viewer.CollapseState
---@return boolean
local function any_hidden(st)
  for id in pairs(st.collapsed) do
    if not st.expanded[id] then
      return true
    end
  end
  return false
end

--- `conceal_lines` only takes effect with 'conceallevel' > 0, and a concealed line under the cursor is revealed
--- unless 'concealcursor' contains the current mode. So while a buffer has hidden blocks, windows showing it get
--- conceallevel 2 (when it was 0) and "n" in concealcursor; both are restored when nothing is hidden anymore.
--- Insert/visual modes are covered by expanding the block (see on_mode), not by concealcursor.
---@param buf number
---@param st mermaid_viewer.CollapseState
local function sync_window_options(buf, st)
  local hidden = any_hidden(st)
  if hidden then
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
      if not st.saved[win] then
        local saved = {}
        if vim.wo[win].conceallevel == 0 then
          saved.conceallevel = 0
          vim.wo[win].conceallevel = 2
        end
        local cc = vim.wo[win].concealcursor
        if not cc:find("n", 1, true) then
          saved.concealcursor = cc
          vim.wo[win].concealcursor = cc .. "n"
        end
        st.saved[win] = saved
      end
    end
    return
  end
  for win, saved in pairs(st.saved) do
    if vim.api.nvim_win_is_valid(win) then
      for opt, value in pairs(saved) do
        vim.wo[win][opt] = value
      end
    end
    st.saved[win] = nil
  end
end

--- Bring the conceal extmarks in line with the state for the buffer's current blocks. Forgets state of blocks
--- that no longer exist.
---@param buf number
---@param list { id: number?, start_row: number, end_row: number }[] resolved blocks
function M.sync(buf, list)
  local st = states[buf]
  if not st then
    return
  end
  local live = {}
  for _, blk in ipairs(list) do
    if blk.id then
      live[blk.id] = true
      local want = st.collapsed[blk.id] and not st.expanded[blk.id]
      if want then
        local last = vim.api.nvim_buf_get_lines(buf, blk.end_row, blk.end_row + 1, false)[1] or ""
        st.marks[blk.id] = vim.api.nvim_buf_set_extmark(buf, ns, blk.start_row, 0, {
          id = st.marks[blk.id],
          end_row = blk.end_row,
          end_col = #last,
          conceal_lines = "",
        })
      elseif st.marks[blk.id] then
        vim.api.nvim_buf_del_extmark(buf, ns, st.marks[blk.id])
        st.marks[blk.id] = nil
      end
    end
  end
  for id in pairs(st.collapsed) do
    if not live[id] then
      M.forget(buf, id)
    end
  end
  sync_window_options(buf, st)
end

---@param buf number
---@param id number
function M.forget(buf, id)
  local st = states[buf]
  if not st then
    return
  end
  if st.marks[id] and vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_del_extmark, buf, ns, st.marks[id])
  end
  st.marks[id] = nil
  st.collapsed[id] = nil
  st.expanded[id] = nil
end

--- Remove all collapse state of a buffer and restore window options
---@param buf number
function M.clear(buf)
  local st = states[buf]
  if not st then
    return
  end
  st.collapsed, st.expanded = {}, {}
  sync_window_options(buf, st)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  end
  states[buf] = nil
end

---@param buf number
local function refresh(buf)
  require("mermaid-viewer.inline").refresh(buf)
end

--- Normal mode: re-collapse every temporarily expanded block except `keep` (the block under the cursor)
---@param buf number
---@param keep? number
function M.recollapse(buf, keep)
  local st = states[buf]
  if not st or not next(st.expanded) then
    return
  end
  local changed = false
  for id in pairs(st.expanded) do
    if id ~= keep then
      st.expanded[id] = nil
      changed = true
    end
  end
  if changed then
    refresh(buf)
  end
end

--- Expand the hidden block under the cursor when an editing mode starts; in normal mode collapse temporarily
--- expanded blocks the cursor has left.
---@param buf number
---@param mode? string defaults to the current mode
function M.on_mode(buf, mode)
  local st = states[buf]
  if not st or not next(st.collapsed) then
    return
  end
  mode = mode or vim.fn.mode()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local id = require("mermaid-viewer.inline").block_at(buf, row)
  local first = mode:sub(1, 1)
  if first:match(EDIT_MODES) then
    if id and M.is_hidden(buf, id) then
      st.expanded[id] = true
      refresh(buf)
    end
  elseif first == "n" then
    M.recollapse(buf, id)
  end
end

local autocmds_ready = false

local function ensure_autocmds()
  if autocmds_ready then
    return
  end
  autocmds_ready = true
  local group = vim.api.nvim_create_augroup("MermaidViewerCollapse", { clear = true })
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = group,
    callback = function(ev)
      M.on_mode(ev.buf, vim.v.event.new_mode or vim.fn.mode())
    end,
  })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    callback = function(ev)
      local st = states[ev.buf]
      if st and next(st.expanded) and vim.fn.mode():sub(1, 1) == "n" then
        M.on_mode(ev.buf, "n")
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    callback = function(ev)
      local st = states[ev.buf]
      if st then
        sync_window_options(ev.buf, st)
      end
    end,
  })
end

--- Toggle collapse of the block at `row` (inside the block, on its fences, or on the row its diagram/marker hangs
--- from). A visible block collapses; a hidden one expands.
---@param buf number
---@param row number 0-based
---@return boolean toggled false when there is no block there
function M.toggle(buf, row)
  if buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end
  local inline = require("mermaid-viewer.inline")
  if not inline.is_enabled(buf) then
    if require("mermaid-viewer.source").block_at(buf, row) then
      vim.notify("mermaid-viewer: inline rendering is off in this buffer (:MermaidInline)", vim.log.levels.WARN)
    else
      vim.notify("No mermaid diagram found at cursor", vim.log.levels.ERROR)
    end
    return false
  end
  local id = inline.block_at(buf, row)
  if not id then
    vim.notify("No mermaid diagram found at cursor", vim.log.levels.ERROR)
    return false
  end
  ensure_autocmds()
  local st = state_for(buf)
  if M.is_hidden(buf, id) then
    st.collapsed[id] = nil
  else
    st.collapsed[id] = true
  end
  st.expanded[id] = nil
  refresh(buf)
  return true
end

--- Reset module state (tests)
function M._reset()
  for buf in pairs(states) do
    M.clear(buf)
  end
  states = {}
  autocmds_ready = false
  pcall(vim.api.nvim_del_augroup_by_name, "MermaidViewerCollapse")
end

return M
