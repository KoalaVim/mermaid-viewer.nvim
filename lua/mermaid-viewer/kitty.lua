---@class mermaid_viewer.Kitty
local M = {}

local CHUNK_SIZE = 4096

local PLACEHOLDER = vim.fn.nr2char(0x10EEEE)

-- Row/column diacritics for Unicode placeholders (kitty rowcolumn-diacritics.txt); also bounds the grid size
local diacritics = {
    "0305", "030D", "030E", "0310", "0312", "033D", "033E", "033F", "0346", "034A", "034B", "034C", "0350", "0351",
    "0352", "0357", "035B", "0363", "0364", "0365", "0366", "0367", "0368", "0369", "036A", "036B", "036C", "036D",
    "036E", "036F", "0483", "0484", "0485", "0486", "0487", "0592", "0593", "0594", "0595", "0597", "0598", "0599",
    "059C", "059D", "059E", "059F", "05A0", "05A1", "05A8", "05A9", "05AB", "05AC", "05AF", "05C4", "0610", "0611",
    "0612", "0613", "0614", "0615", "0616", "0617", "0657", "0658", "0659", "065A", "065B", "065D", "065E", "06D6",
    "06D7", "06D8", "06D9", "06DA", "06DB", "06DC", "06DF", "06E0", "06E1", "06E2", "06E4", "06E7", "06E8", "06EB",
    "06EC", "0730", "0732", "0733", "0735", "0736", "073A", "073D", "073F", "0740", "0741", "0743", "0745", "0747",
    "0749", "074A", "07EB", "07EC", "07ED", "07EE", "07EF", "07F0", "07F1", "07F3", "0816", "0817", "0818", "0819",
    "081B", "081C", "081D", "081E", "081F", "0820", "0821", "0822", "0823", "0825", "0826", "0827", "0829", "082A",
    "082B", "082C", "082D", "0951", "0953", "0954", "0F82", "0F83", "0F86", "0F87", "135D", "135E", "135F", "17DD",
    "193A", "1A17", "1A75", "1A76", "1A77", "1A78", "1A79", "1A7A", "1A7B", "1A7C", "1B6B", "1B6D", "1B6E", "1B6F",
    "1B70", "1B71", "1B72", "1B73", "1CD0", "1CD1", "1CD2", "1CDA", "1CDB", "1CE0", "1DC0", "1DC1", "1DC3", "1DC4",
    "1DC5", "1DC6", "1DC7", "1DC8", "1DC9", "1DCB", "1DCC", "1DD1", "1DD2", "1DD3", "1DD4", "1DD5", "1DD6", "1DD7",
    "1DD8", "1DD9", "1DDA", "1DDB", "1DDC", "1DDD", "1DDE", "1DDF", "1DE0", "1DE1", "1DE2", "1DE3", "1DE4", "1DE5",
    "1DE6", "1DFE", "20D0", "20D1", "20D4", "20D5", "20D6", "20D7", "20DB", "20DC", "20E1", "20E7", "20E9", "20F0",
    "2CEF", "2CF0", "2CF1", "2DE0", "2DE1", "2DE2", "2DE3", "2DE4", "2DE5", "2DE6", "2DE7", "2DE8", "2DE9", "2DEA",
    "2DEB", "2DEC", "2DED", "2DEE", "2DEF", "2DF0", "2DF1", "2DF2", "2DF3", "2DF4", "2DF5", "2DF6", "2DF7", "2DF8",
    "2DF9", "2DFA", "2DFB", "2DFC", "2DFD", "2DFE", "2DFF", "A66F", "A67C", "A67D", "A6F0", "A6F1", "A8E0", "A8E1",
    "A8E2", "A8E3", "A8E4", "A8E5", "A8E6", "A8E7", "A8E8", "A8E9", "A8EA", "A8EB", "A8EC", "A8ED", "A8EE", "A8EF",
    "A8F0", "A8F1", "AAB0", "AAB2", "AAB3", "AAB7", "AAB8", "AABE", "AABF", "AAC1", "FE20", "FE21", "FE22", "FE23",
    "FE24", "FE25", "FE26", "10A0F", "10A38", "1D185", "1D186", "1D187", "1D188", "1D189", "1D1AA", "1D1AB", "1D1AC",
    "1D1AD", "1D242", "1D243", "1D244",
}
local MAX_CELLS = #diacritics

local diacritic_chars = {}
for i, hex in ipairs(diacritics) do
  diacritic_chars[i] = vim.fn.nr2char(tonumber(hex, 16))
end

--- q=2 silences terminal replies; debug mode wants them
---@return number|nil
local function quiet()
  if require("mermaid-viewer.config").options.debug then
    return nil
  end
  return 2
end

---@param params table<string, string|number>
---@param payload? string
---@return string
local function graphics_escape(params, payload)
  local parts = {}
  for k, v in pairs(params) do
    parts[#parts + 1] = k .. "=" .. tostring(v)
  end
  local ctrl = table.concat(parts, ",")
  if payload then
    return "\x1b_G" .. ctrl .. ";" .. payload .. "\x1b\\"
  end
  return "\x1b_G" .. ctrl .. "\x1b\\"
end

--- Write raw bytes to the host terminal.
--- nvim_ui_send (0.12+) goes through the TUI. io.write on the server's non-blocking
--- tty drops whatever doesn't fit in the kernel buffer, truncating image data.
---@param data string
local function send(data)
  if require("mermaid-viewer.config").options.debug then
    require("mermaid-viewer.terminal").attach_debug()
  end
  if vim.api.nvim_ui_send then
    vim.api.nvim_ui_send(data)
  else
    io.write(data)
    io.flush()
  end
end

--- Build the chunked transmit sequence for a PNG (no output)
---@param png_path string
---@param id number
---@return string|nil
local function transmit_seq(png_path, id)
  local f = io.open(png_path, "rb")
  if not f then
    return nil
  end
  local data = f:read("*a")
  f:close()

  local encoded = vim.base64.encode(data)
  local chunks = {}
  for i = 1, #encoded, CHUNK_SIZE do
    chunks[#chunks + 1] = encoded:sub(i, i + CHUNK_SIZE - 1)
  end

  -- All chunks go out in one write; separate writes can be interleaved with TUI output
  local seq = {}
  for i, chunk in ipairs(chunks) do
    local params
    if i == 1 then
      params = {
        a = "t",
        i = id,
        f = 100,
        t = "d",
        q = quiet(),
        C = 1,
        m = (#chunks > 1) and 1 or 0,
      }
    else
      params = { m = (i < #chunks) and 1 or 0 }
    end
    seq[#seq + 1] = graphics_escape(params, chunk)
  end
  return table.concat(seq)
end

--- Transmit a PNG and create its virtual placement (for Unicode placeholders) in a single write
---@param png_path string
---@param id number 24-bit image id
---@param cols number
---@param rows number
---@return boolean
function M.transmit_virtual(png_path, id, cols, rows)
  local seq = transmit_seq(png_path, id)
  if not seq then
    return false
  end
  send(seq .. graphics_escape({ a = "p", U = 1, i = id, c = cols, r = rows, q = quiet() }))
  return true
end

--- Delete an image and free its data from the terminal
---@param id number
function M.delete_image(id)
  send(graphics_escape({ a = "d", d = "I", i = id, q = quiet() }))
end

---@param id number
---@return string
function M.highlight_name(id)
  return "MermaidViewerImage" .. id
end

--- Highlight whose fg encodes the image id; placeholder cells drawn with it show that image
---@param id number
---@return string name
function M.set_highlight(id)
  local name = M.highlight_name(id)
  vim.api.nvim_set_hl(0, name, { fg = id, nocombine = true })
  return name
end

---@param id number
function M.clear_highlight(id)
  vim.api.nvim_set_hl(0, M.highlight_name(id), {})
end

---@class mermaid_viewer.GridRange
---@field row_start? number 1-indexed first row (default 1)
---@field row_end? number last row (default rows)
---@field col_start? number 1-indexed first column (default 1)
---@field col_end? number last column (default cols)

--- Placeholder text per row for a cols x rows image grid. Each cell is U+10EEEE + row + column diacritic, so
--- sub-ranges still address the right image cells. Sizes are capped at the diacritics table length.
---@param cols number
---@param rows number
---@param range? mermaid_viewer.GridRange
---@return string[]
function M.placeholder_lines(cols, rows, range)
  range = range or {}
  local r1, r2 = range.row_start or 1, math.min(range.row_end or rows, rows, MAX_CELLS)
  local c1, c2 = range.col_start or 1, math.min(range.col_end or cols, cols, MAX_CELLS)
  local lines = {}
  for r = r1, r2 do
    local row = diacritic_chars[r]
    local cells = {}
    for c = c1, c2 do
      cells[#cells + 1] = PLACEHOLDER .. row .. diacritic_chars[c]
    end
    lines[#lines + 1] = table.concat(cells)
  end
  return lines
end

--- Same grid as extmark virt_lines: one `{ { text, hl } }` list per row
---@param cols number
---@param rows number
---@param hl string highlight group from set_highlight()
---@param range? mermaid_viewer.GridRange
---@return { [1]: string, [2]: string }[][]
function M.placeholder_virt_lines(cols, rows, hl, range)
  local virt = {}
  for _, line in ipairs(M.placeholder_lines(cols, rows, range)) do
    virt[#virt + 1] = { { line, hl } }
  end
  return virt
end

---@type number
M.max_cells = MAX_CELLS

local FALLBACK_CELL = { width = 10, height = 20 }

local ffi_ok, ffi = pcall(require, "ffi")
if ffi_ok then
  pcall(ffi.cdef, [[
    struct mermaid_viewer_winsize { unsigned short ws_row, ws_col, ws_xpixel, ws_ypixel; };
    int ioctl(int fd, unsigned long request, ...);
  ]])
end

--- Cell size in pixels, read from the tty via TIOCGWINSZ
---@return { width: number, height: number }
function M.cell_size()
  if not ffi_ok then
    return FALLBACK_CELL
  end
  local TIOCGWINSZ = ffi.os == "OSX" and 0x40087468 or 0x5413
  local ws = ffi.new("struct mermaid_viewer_winsize")
  for _, fd in ipairs({ 1, 2, 0 }) do
    local ok, ret = pcall(ffi.C.ioctl, fd, TIOCGWINSZ, ws)
    if ok and ret == 0 and ws.ws_col > 0 and ws.ws_row > 0 and ws.ws_xpixel > 0 and ws.ws_ypixel > 0 then
      return { width = ws.ws_xpixel / ws.ws_col, height = ws.ws_ypixel / ws.ws_row }
    end
  end
  return FALLBACK_CELL
end

return M
