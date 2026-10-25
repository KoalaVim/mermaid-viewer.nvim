---@class mermaid_viewer.Source
local M = {}

local config = require("mermaid-viewer.config")

---@alias mermaid_viewer.SourceKind "markdown"|"mermaid"|"terminal"

--- How the buffer holds diagrams: ```mermaid blocks (markdown), the whole buffer (mermaid filetype or *.mmd), or
--- agent output in a terminal buffer (filetype listed in `terminal_filetypes`). nil for anything else.
---@param bufnr number
---@return mermaid_viewer.SourceKind|nil
function M.kind(bufnr)
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local ft = vim.bo[bufnr].filetype
  if ft == "markdown" then
    return "markdown"
  end
  if ft == "mermaid" or vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":e") == "mmd" then
    return "mermaid"
  end
  if vim.tbl_contains(config.options.terminal_filetypes, ft) then
    return "terminal"
  end
  return nil
end

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
---@field below? boolean the diagram goes under the last row instead of above the first (whole buffers, terminals)

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

--- First words of a mermaid diagram declaration
local DIAGRAM_TYPES = {}
for _, t in ipairs({
  "flowchart", "graph", "sequenceDiagram", "classDiagram", "classDiagram-v2", "stateDiagram", "stateDiagram-v2",
  "erDiagram", "journey", "gantt", "pie", "gitGraph", "mindmap", "timeline", "quadrantChart", "requirementDiagram",
  "C4Context", "C4Container", "C4Component", "C4Dynamic", "C4Deployment", "xychart-beta", "sankey-beta",
  "block-beta", "packet-beta", "architecture-beta", "kanban", "radar-beta",
}) do
  DIAGRAM_TYPES[t] = true
end

--- A diagram declaration line, e.g. "flowchart TD" or "sequenceDiagram". Strict, so prose does not match.
---@param line string
---@return string|nil indent
local function declaration(line)
  -- cheap first-word check: most lines are prose
  local s = line:find("%S")
  local word = s and line:match("^[%w%-]+", s)
  if not word or not DIAGRAM_TYPES[word] then
    return nil
  end
  local rest = vim.trim(line:sub(s + #word))
  local indent = line:sub(1, s - 1)
  if rest == "" or rest == ":" then
    return indent
  end
  if (word == "flowchart" or word == "graph") and rest:match("^[TBLRD][TBLRD];?$") then
    return indent
  end
  if (word == "pie" or word == "xychart-beta") and line:sub(s + #word, s + #word):match("%s") then
    return indent
  end
  return nil
end

--- Rows above the windows scanned for the start of a diagram that reaches into view
local TERMINAL_LOOKBACK = 100
--- Longest diagram followed past the scanned rows
local TERMINAL_MAX_BLOCK = 500

--- 0-based rows of a terminal buffer worth scanning: around the windows showing it (one window height above and
--- below, plus TERMINAL_LOOKBACK above). The whole buffer when no window shows it.
---@param bufnr number
---@return number first
---@return number last
local function terminal_range(bufnr)
  local first, last
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    local info = vim.fn.getwininfo(win)[1]
    local top = info.topline - 1 - info.height - TERMINAL_LOOKBACK
    local bot = info.botline - 1 + info.height
    first = first and math.min(first, top) or top
    last = last and math.max(last, bot) or bot
  end
  local count = vim.api.nvim_buf_line_count(bufnr)
  if not first then
    return 0, count - 1
  end
  return math.max(0, first), math.min(count - 1, last)
end

--- Lines of the buffer by 1-based index, read in chunks on demand
---@param bufnr number
---@return fun(i: number): string|nil
local function line_reader(bufnr)
  local cache, count = {}, vim.api.nvim_buf_line_count(bufnr)
  return function(i)
    if i < 1 or i > count then
      return nil
    end
    if cache[i] == nil then
      local chunk = vim.api.nvim_buf_get_lines(bufnr, i - 1, math.min(count, i + 199), false)
      for k, l in ipairs(chunk) do
        cache[i + k - 1] = l
      end
    end
    return cache[i]
  end
end

---@param get fun(i: number): string|nil
---@param first number 1-based
---@param last number 1-based
---@param indent number columns to strip
---@return string
local function dedent(get, first, last, indent)
  local out = {}
  for i = first, last do
    local line = get(i):gsub("%s+$", "")
    out[#out + 1] = line:sub(1, indent):match("^%s*$") and line:sub(indent + 1) or vim.trim(line)
  end
  return table.concat(out, "\n")
end

--- Diagrams in an agent's terminal output: ```mermaid fences (at any indent), and diagrams an agent's UI prints
--- without fences: a declaration line ("flowchart TD", "sequenceDiagram", ...) followed by more-indented lines.
--- The diagram ends before the next non-blank line indented no more than its declaration.
--- Only diagrams starting in rows first..last (1-based) are found; one that runs past `last` is followed to its end.
---@param get fun(i: number): string|nil
---@param first number
---@param last number
---@return mermaid_viewer.Block[]
local function blocks_terminal(get, first, last)
  local blocks = {}
  local i = first
  while i <= last do
    local line = get(i)
    if not line then
      break
    end
    local fence = line:find("```", 1, true) and line:match("^(%s*)```+%s*mermaid%s*$")
    local indent = not fence and declaration(line)
    if fence then
      local close
      for j = i + 1, i + TERMINAL_MAX_BLOCK do
        local l = get(j)
        if not l then
          break
        end
        if l:match("^%s*```+%s*$") then
          close = j
          break
        end
      end
      if close then
        blocks[#blocks + 1] = {
          start_row = i - 1,
          end_row = close - 1,
          content_start = i,
          content_end = close - 2,
          content = dedent(get, i + 1, close - 1, #fence),
          info = "mermaid",
          below = true,
        }
        i = close
      end
    elseif indent then
      local stop = i
      for j = i + 1, i + TERMINAL_MAX_BLOCK do
        local l = get(j)
        if not l then
          break
        end
        local lead = l:find("%S")
        if not lead then
          -- blank lines belong to the diagram only when more of it follows
        elseif lead - 1 > #indent then
          stop = j
        else
          break
        end
      end
      if stop > i then
        blocks[#blocks + 1] = {
          start_row = i - 1,
          end_row = stop - 1,
          content_start = i - 1,
          content_end = stop - 1,
          content = dedent(get, i, stop, #indent),
          info = "mermaid",
          below = true,
        }
        i = stop
      end
    end
    i = i + 1
  end
  return blocks
end

--- The buffer's diagrams, in document order: terminated ```mermaid fenced blocks of a markdown buffer (treesitter,
--- falling back to a line scan), the whole buffer of a mermaid/*.mmd buffer, or the diagrams in an agent terminal's
--- output around the windows showing it (all of it when none does). Other buffers yield no blocks.
---@param bufnr number Buffer handle (0 for current)
---@return mermaid_viewer.Block[]
function M.blocks(bufnr)
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local kind = M.kind(bufnr)
  if not kind then
    return {}
  end
  if kind == "terminal" then
    local first, last = terminal_range(bufnr)
    return blocks_terminal(line_reader(bufnr), first + 1, last + 1)
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if kind == "markdown" then
    return blocks_treesitter(bufnr, lines) or blocks_line_scan(lines)
  end
  local content = table.concat(lines, "\n")
  if not content:match("%S") then
    return {}
  end
  return {
    {
      start_row = 0,
      end_row = #lines - 1,
      content_start = 0,
      content_end = #lines - 1,
      content = content,
      info = "mermaid",
      below = true,
    },
  }
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

  local kind = M.kind(bufnr)

  if kind == "mermaid" then
    return extract_full_buffer(bufnr)
  end

  if kind == "markdown" or kind == "terminal" then
    local block = M.block_at(bufnr, vim.api.nvim_win_get_cursor(0)[1] - 1)
    if block then
      return block.content, nil
    end
    return nil, "No mermaid diagram found at cursor"
  end

  return nil, "Unsupported filetype"
end

return M
