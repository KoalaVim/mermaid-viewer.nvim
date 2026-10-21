---@class mermaid_viewer.Blocks
local M = {}

local source = require("mermaid-viewer.source")
local debounce = require("mermaid-viewer.debounce")

local ns = vim.api.nvim_create_namespace("mermaid_viewer_blocks")

---@class mermaid_viewer.TrackedBlock : mermaid_viewer.Block
---@field id number anchor extmark id, stable while the block exists
---@field hash string sha256 of the content

---@class mermaid_viewer.BlockDiff
---@field added mermaid_viewer.TrackedBlock[]
---@field removed mermaid_viewer.TrackedBlock[] last known content/range, hash of the old content
---@field changed mermaid_viewer.TrackedBlock[] content differs from the previous scan
---@field unchanged mermaid_viewer.TrackedBlock[]

---@class mermaid_viewer.BlocksState
---@field hashes table<number, string> anchor id -> content hash at the last scan
---@field last table<number, mermaid_viewer.TrackedBlock> anchor id -> block at the last scan
---@field augroup? number
---@field on_diff? fun(diff: mermaid_viewer.BlockDiff)

---@type table<number, mermaid_viewer.BlocksState>
local states = {}

---@param bufnr number
---@return mermaid_viewer.BlocksState
local function state_for(bufnr)
  if not states[bufnr] then
    states[bufnr] = { hashes = {}, last = {} }
  end
  return states[bufnr]
end

---@param diff mermaid_viewer.BlockDiff
---@return boolean
local function has_changes(diff)
  return #diff.added > 0 or #diff.removed > 0 or #diff.changed > 0
end

---@param bufnr number
---@param id number
---@return number|nil row
local function anchor_row(bufnr, id)
  local pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, id, {})
  return pos[1]
end

--- Reconcile the buffer's current mermaid blocks with the existing anchors.
--- Anchors are matched to blocks by position (anchor row == opening fence row), so a block keeps
--- its id across edits above it. Anchors without a block are deleted and reported as removed.
---@param bufnr number
---@return mermaid_viewer.BlockDiff
function M.scan(bufnr)
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local st = state_for(bufnr)
  local diff = { added = {}, removed = {}, changed = {}, unchanged = {} }

  ---@type table<number, number[]> row -> anchor ids sitting there
  local by_row = {}
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})) do
    local row = mark[2]
    by_row[row] = by_row[row] or {}
    table.insert(by_row[row], mark[1])
  end

  local claimed = {}
  local next_last = {}
  for _, block in ipairs(source.blocks(bufnr)) do
    local hash = vim.fn.sha256(block.content)
    local ids = by_row[block.start_row] or {}
    -- several anchors on one row happens when a block above was deleted; prefer the unchanged one
    local id
    for _, cand in ipairs(ids) do
      if st.hashes[cand] == hash then
        id = cand
        break
      end
    end
    id = id or ids[1]

    ---@type mermaid_viewer.TrackedBlock
    local tracked = vim.tbl_extend("force", block, { hash = hash, id = 0 })
    if id then
      by_row[block.start_row] = vim.tbl_filter(function(x)
        return x ~= id
      end, ids)
      tracked.id = id
      table.insert(st.hashes[id] == hash and diff.unchanged or diff.changed, tracked)
    else
      tracked.id = vim.api.nvim_buf_set_extmark(bufnr, ns, block.start_row, 0, {})
      table.insert(diff.added, tracked)
    end
    claimed[tracked.id] = true
    next_last[tracked.id] = tracked
  end

  for id, prev in pairs(st.last) do
    if not claimed[id] then
      table.insert(diff.removed, prev)
    end
  end
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})) do
    if not claimed[mark[1]] then
      vim.api.nvim_buf_del_extmark(bufnr, ns, mark[1])
    end
  end

  st.last = next_last
  st.hashes = {}
  for id, b in pairs(next_last) do
    st.hashes[id] = b.hash
  end
  for _, list in pairs(diff) do
    table.sort(list, function(a, b)
      return a.start_row < b.start_row
    end)
  end
  return diff
end

--- Current range and content of an anchored block. Read-only: does not create anchors or alter scan state.
---@param bufnr number
---@param anchor_id number
---@return mermaid_viewer.TrackedBlock|nil nil when the anchor or its block vanished
function M.get(bufnr, anchor_id)
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  local row = anchor_row(bufnr, anchor_id)
  if not row then
    return nil
  end
  for _, block in ipairs(source.blocks(bufnr)) do
    if block.start_row == row then
      return vim.tbl_extend("force", block, { id = anchor_id, hash = vim.fn.sha256(block.content) })
    end
  end
  return nil
end

--- The block containing `row` (fences included). `id` is the anchor id as of the last scan, and 0 for
--- a block that has not been scanned yet. Read-only.
---@param bufnr number
---@param row number 0-based
---@return mermaid_viewer.TrackedBlock|nil
function M.at_row(bufnr, row)
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local block = source.block_at(bufnr, row)
  if not block then
    return nil
  end
  local id = 0
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, { block.start_row, 0 }, { block.start_row, -1 }, {})
  if marks[1] then
    id = marks[1][1]
  end
  return vim.tbl_extend("force", block, { id = id, hash = vim.fn.sha256(block.content) })
end

--- Track the buffer: scan now and after every debounced change, calling `on_diff` only when a block was
--- added, removed or changed. The initial scan reports existing blocks as added. Calling it again on an
--- attached buffer only replaces the callback.
---@param bufnr number
---@param on_diff fun(diff: mermaid_viewer.BlockDiff)
function M.attach(bufnr, on_diff)
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local st = state_for(bufnr)
  st.on_diff = on_diff
  if st.augroup then
    return
  end

  local function rescan()
    if not vim.api.nvim_buf_is_valid(bufnr) or not states[bufnr] then
      return
    end
    local diff = M.scan(bufnr)
    if has_changes(diff) and states[bufnr].on_diff then
      states[bufnr].on_diff(diff)
    end
  end

  st.augroup = debounce.watch(bufnr, rescan, "blocks")
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = st.augroup,
    buffer = bufnr,
    callback = function()
      M.detach(bufnr)
    end,
  })
  rescan()
end

--- Stop tracking: remove the watcher, anchors and scan state.
---@param bufnr number
function M.detach(bufnr)
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local st = states[bufnr]
  if st and st.augroup then
    debounce.stop(st.augroup)
  end
  states[bufnr] = nil
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  end
end

return M
