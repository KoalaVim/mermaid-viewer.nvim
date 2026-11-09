--- Fullscreen TUIs repaint buffer rows instead of moving scrollback. Use overlays, never virtual lines.
local M = {}
local ns = vim.api.nvim_create_namespace("mermaid_viewer_fullscreen")
local marks = {}

function M.enabled(buf)
  if not vim.api.nvim_buf_is_valid(buf) or require("mermaid-viewer.source").kind(buf) ~= "terminal" then
    return false
  end
  local override = vim.b[buf].mermaid_viewer_fullscreen
  if override ~= nil then
    return override == true
  end
  return require("mermaid-viewer.config").options.terminal.fullscreen == true
end

function M.clear(buf, id)
  if id then
    local entry = marks[buf] and marks[buf][id]
    for _, mark in ipairs(entry and entry.ids or {}) do
      pcall(vim.api.nvim_buf_del_extmark, buf, ns, mark)
    end
    if marks[buf] then
      marks[buf][id] = nil
    end
  else
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    end
    marks[buf] = nil
  end
end

--- Cursor/selection/footer repaints must not blank unchanged diagrams. Compare only overlaid source rows.
function M.invalidate(buf)
  local stale = {}
  for id, entry in pairs(marks[buf] or {}) do
    local text = vim.api.nvim_buf_get_lines(buf, entry.first, entry.last + 1, false)
    if not vim.deep_equal(text, entry.text) then
      stale[#stale + 1] = id
    end
  end
  for _, id in ipairs(stale) do
    M.clear(buf, id)
  end
end

function M.place(buf, block, image)
  if not image then
    M.clear(buf, block.id)
    return
  end
  marks[buf] = marks[buf] or {}
  local entry = marks[buf][block.id]
  local count = math.min(image.rows, block.content_end - block.content_start + 1)
  local first, last = block.content_start, block.content_start + count - 1
  local text = vim.api.nvim_buf_get_lines(buf, first, last + 1, false)
  local unchanged = entry and entry.first == first and entry.last == last
    and entry.hl == image.hl and entry.cols == image.cols and vim.deep_equal(entry.text, text)
  if unchanged then
    for i, id in ipairs(entry.ids) do
      local pos = vim.api.nvim_buf_get_extmark_by_id(buf, ns, id, {})
      if pos[1] ~= first + i - 1 then
        unchanged = false
        break
      end
    end
  end
  if unchanged then
    return
  end
  -- Reuse extmark ids when geometry changes instead of deleting/recreating an unchanged image.
  local old_ids = entry and entry.ids or {}
  local ids = {}
  local lines = require("mermaid-viewer.kitty").placeholder_virt_lines(image.cols, image.rows, image.hl)
  for i = 1, count do
    ids[i] = vim.api.nvim_buf_set_extmark(buf, ns, first + i - 1, 0, {
      id = old_ids[i],
      virt_text = lines[i],
      virt_text_pos = "overlay",
      virt_text_win_col = 0,
      priority = 200,
    })
  end
  for i = count + 1, #old_ids do
    pcall(vim.api.nvim_buf_del_extmark, buf, ns, old_ids[i])
  end
  marks[buf][block.id] = { ids = ids, first = first, last = last, text = text, hl = image.hl, cols = image.cols }
end

--- Hit-test actual overlay cells; do not send diagram double-clicks through to the application's selection handler.
function M.at_mouse(pos)
  if not vim.api.nvim_win_is_valid(pos.winid) then
    return nil
  end
  local buf = vim.api.nvim_win_get_buf(pos.winid)
  for id, entry in pairs(marks[buf] or {}) do
    for _, mark in ipairs(entry.ids) do
      local row = vim.api.nvim_buf_get_extmark_by_id(buf, ns, mark, {})[1]
      if row then
        local screen = vim.fn.screenpos(pos.winid, row + 1, 1)
        local info = vim.fn.getwininfo(pos.winid)[1]
        local left = info.wincol + info.textoff
        if screen.row > 0 and pos.screenrow == screen.row
          and pos.screencol >= left and pos.screencol < left + entry.cols then
          return id
        end
      end
    end
  end
end

return M
