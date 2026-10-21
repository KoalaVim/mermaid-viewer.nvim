---@class mermaid_viewer.Source
local M = {}

---@param bufnr number
---@return string|nil source
---@return string|nil error
local function extract_full_buffer(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if #lines == 0 or (#lines == 1 and lines[1] == "") then
    return nil, "Buffer is empty"
  end
  return table.concat(lines, "\n"), nil
end

---@class mermaid_viewer.Block
---@field start_row number 0-based row of the opening fence
---@field end_row number 0-based row of the closing fence
---@field content_start number 0-based first content row (== end_row for an empty block)
---@field content_end number 0-based last content row, inclusive (== start_row for an empty block)
---@field content string block source, lines joined with "\n"
---@field info string text after the opening ``` (e.g. "mermaid {theme=dark}")

---@param lines string[]
---@param start_row number
---@param end_row number
---@param info string
---@return mermaid_viewer.Block
local function make_block(lines, start_row, end_row, info)
  local content_lines = {}
  for r = start_row + 1, end_row - 1 do
    content_lines[#content_lines + 1] = lines[r + 1]
  end
  return {
    start_row = start_row,
    end_row = end_row,
    content_start = start_row + 1,
    content_end = end_row - 1,
    content = table.concat(content_lines, "\n"),
    info = info,
  }
end

---@param info string
---@return boolean
local function is_mermaid_info(info)
  return info:match("^mermaid$") ~= nil or info:match("^mermaid[%s{]") ~= nil
end

---@param bufnr number
---@param lines string[]
---@return mermaid_viewer.Block[]|nil nil when treesitter is unavailable
local function blocks_treesitter(bufnr, lines)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "markdown")
  if not ok or not parser then
    return nil
  end
  local trees = parser:parse()
  if not trees or #trees == 0 then
    return nil
  end

  local query = vim.treesitter.query.parse("markdown", "(fenced_code_block) @block")
  local blocks = {}
  for _, tree in ipairs(trees) do
    for _, node in query:iter_captures(tree:root(), bufnr, 0, -1) do
      local lang, delims = nil, {}
      for child in node:iter_children() do
        local t = child:type()
        if t == "info_string" then
          lang = vim.treesitter.get_node_text(child, bufnr)
        elseif t == "fenced_code_block_delimiter" then
          delims[#delims + 1] = child
        end
      end
      -- an unterminated block only has its opening delimiter
      if lang and #delims >= 2 and is_mermaid_info(vim.trim(lang)) then
        local start_row = delims[1]:range()
        local end_row = delims[#delims]:range()
        blocks[#blocks + 1] = make_block(lines, start_row, end_row, vim.trim(lang))
      end
    end
  end
  table.sort(blocks, function(a, b)
    return a.start_row < b.start_row
  end)
  return blocks
end

---@param lines string[]
---@return mermaid_viewer.Block[]
local function blocks_line_scan(lines)
  local blocks = {}
  local open_row, open_info = nil, nil
  for i, line in ipairs(lines) do
    if open_row == nil then
      local info = line:match("^```(mermaid.*)$")
      if info and is_mermaid_info(vim.trim(info)) then
        open_row, open_info = i - 1, vim.trim(info)
      end
    elseif line:match("^```%s*$") then
      blocks[#blocks + 1] = make_block(lines, open_row, i - 1, open_info)
      open_row = nil
    end
  end
  return blocks
end

--- All terminated ```mermaid fenced blocks of a markdown buffer, in document order.
--- Uses the treesitter markdown parser, falling back to a line scan. Other filetypes yield no blocks.
---@param bufnr number Buffer handle (0 for current)
---@return mermaid_viewer.Block[]
function M.blocks(bufnr)
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  if vim.bo[bufnr].filetype ~= "markdown" then
    return {}
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return blocks_treesitter(bufnr, lines) or blocks_line_scan(lines)
end

--- The block whose lines (fences included) contain `row`.
---@param bufnr number
---@param row number 0-based
---@return mermaid_viewer.Block|nil
function M.block_at(bufnr, row)
  for _, block in ipairs(M.blocks(bufnr)) do
    if row >= block.start_row and row <= block.end_row then
      return block
    end
  end
  return nil
end

--- Extract the source of the block currently held by a blocks.lua anchor.
---@param bufnr number
---@param anchor_id number extmark id from mermaid-viewer.blocks
---@return string|nil source
---@return string|nil error
function M.extract_anchor(bufnr, anchor_id)
  local block = require("mermaid-viewer.blocks").get(bufnr, anchor_id)
  if not block then
    return nil, "Mermaid block no longer exists"
  end
  return block.content, nil
end

--- Extract mermaid source from the given buffer.
---@param bufnr number Buffer handle (0 for current)
---@return string|nil source The extracted mermaid source, or nil on failure
---@return string|nil error Error message if extraction failed
function M.extract(bufnr)
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end

  local ft = vim.bo[bufnr].filetype

  if ft == "mermaid" then
    return extract_full_buffer(bufnr)
  end

  if ft ~= "mermaid" and ft ~= "markdown" then
    local ext = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":e")
    if ext == "mmd" then
      return extract_full_buffer(bufnr)
    end
  end

  if ft == "markdown" then
    local block = M.block_at(bufnr, vim.api.nvim_win_get_cursor(0)[1] - 1)
    if block then
      return block.content, nil
    end
    return nil, "No mermaid diagram found at cursor"
  end

  return nil, "Unsupported filetype"
end

return M
