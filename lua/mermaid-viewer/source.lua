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

---@param bufnr number
---@return string|nil source
---@return string|nil error
local function extract_treesitter(bufnr)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "markdown")
  if not ok or not parser then
    return nil, nil
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_row = cursor[1] - 1

  local trees = parser:parse()
  if not trees or #trees == 0 then
    return nil, nil
  end

  local query = vim.treesitter.query.parse("markdown", [[
    (fenced_code_block
      (info_string (language) @lang)
      (code_fence_content) @content)
  ]])

  for _, tree in ipairs(trees) do
    for id, node, _ in query:iter_captures(tree:root(), bufnr, 0, -1) do
      local name = query.captures[id]
      if name == "lang" then
        local lang_text = vim.treesitter.get_node_text(node, bufnr)
        if lang_text:match("^mermaid") then
          local parent = node:parent():parent()
          local start_row, _, end_row, _ = parent:range()
          if cursor_row >= start_row and cursor_row <= end_row then
            local sibling = node:parent():next_named_sibling()
            while sibling do
              if sibling:type() == "code_fence_content" then
                local text = vim.treesitter.get_node_text(sibling, bufnr)
                text = text:gsub("\n$", "")
                return text, nil
              end
              sibling = sibling:next_named_sibling()
            end
          end
        end
      end
    end
  end

  return nil, "No mermaid diagram found at cursor"
end

---@param bufnr number
---@return string|nil source
---@return string|nil error
local function extract_line_scan(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor[1]

  ---@type { start_line: number, end_line: number }[]
  local blocks = {}
  local current_start = nil

  for i, line in ipairs(lines) do
    if current_start == nil then
      if line:match("^```mermaid") then
        current_start = i
      end
    else
      if line:match("^```%s*$") then
        table.insert(blocks, { start_line = current_start, end_line = i })
        current_start = nil
      end
    end
  end

  for _, block in ipairs(blocks) do
    if cursor_line >= block.start_line and cursor_line <= block.end_line then
      local content_lines = {}
      for i = block.start_line + 1, block.end_line - 1 do
        table.insert(content_lines, lines[i])
      end
      return table.concat(content_lines, "\n"), nil
    end
  end

  return nil, "No mermaid diagram found at cursor"
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
    local source, err = extract_treesitter(bufnr)
    if source then
      return source, nil
    end
    -- err is nil when treesitter wasn't available, fall through to line scan
    -- err is non-nil when treesitter worked but found no block at cursor
    if err then
      return nil, err
    end
    return extract_line_scan(bufnr)
  end

  return nil, "Unsupported filetype"
end

return M
