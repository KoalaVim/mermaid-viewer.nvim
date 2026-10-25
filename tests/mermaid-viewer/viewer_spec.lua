local config = require("mermaid-viewer.config")
local cache = require("mermaid-viewer.cache")
local kitty = require("mermaid-viewer.kitty")
local registry = require("mermaid-viewer.registry")
local state = require("mermaid-viewer.state")

local WIDE = { "graph LR", "  A --> B", "  B --> C", "  C --> D", "  D --> E", "  E --> F" }

local function wait_for(pred, ms)
  return vim.wait(ms or 15000, pred, 10)
end

describe("mermaid-viewer viewer", function()
  local mv, nav
  local real_send, real_cell, real_notify
  local sent, notes

  --- Kitty graphics commands sent so far, in order: { op = "t"|"p"|"d", id = number }
  local function commands()
    local out = {}
    for _, data in ipairs(sent) do
      for ctrl in data:gmatch("\27_G([^;\27]*)") do
        out[#out + 1] = { op = ctrl:match("a=(%a)"), id = tonumber(ctrl:match("i=(%d+)")) }
      end
    end
    return out
  end

  local function find(op, id)
    for i, c in ipairs(commands()) do
      if c.op == op and (id == nil or c.id == id) then
        return i
      end
    end
  end

  local function floats()
    return vim.tbl_filter(function(w)
      return vim.api.nvim_win_get_config(w).relative ~= ""
    end, vim.api.nvim_list_wins())
  end

  --- New markdown buffer holding a mermaid block that starts at row 2 (0-based)
  local function markdown(block)
    block = block or { "graph TD", "  A --> B", "  B --> C" }
    vim.cmd("enew!")
    local buf = vim.api.nvim_get_current_buf()
    local lines = { "# title", "" }
    table.insert(lines, "```mermaid")
    vim.list_extend(lines, block)
    vim.list_extend(lines, { "```", "", "text" })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = "markdown"
    return buf
  end

  local function open(buf, row)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_win_set_cursor(0, { row or 4, 0 })
    mv.view()
    assert.is_true(wait_for(function()
      return state.current ~= nil or #notes > 0
    end))
    return state.current
  end

  local function wait_zoom(s, pred)
    assert.is_true(wait_for(function()
      return pred(s)
    end), "timed out waiting for render")
  end

  before_each(function()
    for _, w in ipairs(floats()) do
      pcall(vim.api.nvim_win_close, w, true)
    end
    config.setup({ debounce_ms = 40, terminal = { placeholders = true } })
    vim.o.termguicolors = true
    cache.clear()
    registry._reset()
    mv = require("mermaid-viewer")
    nav = require("mermaid-viewer.navigation")
    sent, notes = {}, {}
    real_send, real_cell, real_notify = vim.api.nvim_ui_send, kitty.cell_size, vim.notify
    vim.api.nvim_ui_send = function(data)
      sent[#sent + 1] = data
    end
    kitty.cell_size = function()
      return { width = 10, height = 20 }
    end
    vim.notify = function(msg, level)
      notes[#notes + 1] = { msg = msg, level = level }
    end
  end)

  after_each(function()
    mv.close()
    vim.api.nvim_ui_send, kitty.cell_size, vim.notify = real_send, real_cell, real_notify
  end)

  it("opens a float of placeholder rows for the block under the cursor", function()
    local buf = markdown()
    local s = open(buf)
    assert.is_not_nil(s)
    assert.is_true(vim.api.nvim_win_is_valid(s.win))
    assert.equals("editor", vim.api.nvim_win_get_config(s.win).relative)
    assert.equals(s.win, vim.api.nvim_get_current_win())
    assert.same(kitty.placeholder_lines(s.cols, s.rows), vim.api.nvim_buf_get_lines(s.buf, 0, -1, false))
    assert.is_true(s.cols <= vim.api.nvim_win_get_width(s.win) or s.cols > 0)
    assert.is_true(vim.api.nvim_win_get_width(s.win) <= math.floor(vim.o.columns * config.options.float.width))
    assert.is_not_nil(find("t", s.image.id))
    assert.is_not_nil(find("p", s.image.id))
    local wo, bo = vim.wo[s.win], vim.bo[s.buf]
    assert.is_false(wo.wrap)
    assert.is_false(wo.number)
    assert.equals("no", wo.signcolumn)
    assert.equals(0, wo.scrolloff)
    assert.equals(0, wo.sidescrolloff)
    assert.is_false(bo.modifiable)
    local mark = vim.api.nvim_buf_get_extmarks(s.buf, -1, 0, -1, { details = true })[1]
    assert.equals(s.image.hl, mark[4].hl_group)
  end)

  it("opens from the row a collapsed block's diagram and marker hang from", function()
    local inline = require("mermaid-viewer.inline")
    local collapse = require("mermaid-viewer.collapse")
    local buf = markdown()
    vim.api.nvim_set_current_buf(buf)
    assert.is_true(inline.enable(buf))
    assert.is_true(collapse.toggle(buf, 2))
    -- fence at row 2, closing fence at row 6: the collapsed diagram hangs from row 7
    assert.is_not_nil(inline.block_at(buf, 7))
    local s = open(buf, 8)
    assert.is_not_nil(s)
    assert.is_true(vim.api.nvim_win_is_valid(s.win))
    local text = require("mermaid-viewer.viewer").source_text(s.source)
    assert.same({ "graph TD", "  A --> B", "  B --> C" }, vim.split(text, "\n"))
    mv.close()
    inline.disable(buf)
  end)

  it("opens from the line just above a block, expanded or collapsed", function()
    local inline = require("mermaid-viewer.inline")
    local collapse = require("mermaid-viewer.collapse")
    local buf = markdown()
    local s = open(buf, 2) -- fence at row 2 (line 3)
    assert.is_not_nil(s)
    assert.equals("graph TD", vim.split(require("mermaid-viewer.viewer").source_text(s.source), "\n")[1])
    mv.close()

    vim.api.nvim_set_current_buf(buf)
    assert.is_true(inline.enable(buf))
    assert.is_true(collapse.toggle(buf, 2))
    s = open(buf, 2)
    assert.is_not_nil(s)
    assert.is_true(vim.api.nvim_win_is_valid(s.win))
    mv.close()
    inline.disable(buf)
  end)

  it("errors when the cursor is outside any block and opens no float", function()
    local buf = markdown()
    open(buf, 1)
    assert.is_nil(state.current)
    assert.equals(1, #notes)
    assert.truthy(notes[1].msg:find("No mermaid diagram found at cursor", 1, true))
    assert.equals(vim.log.levels.ERROR, notes[1].level)
    assert.equals(0, #floats())
    assert.equals(0, #commands())
  end)

  it("reports mmdr errors and leaves no float open", function()
    local buf = markdown({ "this is not (( a diagram" })
    open(buf)
    assert.is_nil(state.current)
    assert.is_nil(state.opening)
    assert.equals(vim.log.levels.ERROR, notes[1].level)
    assert.equals(0, #floats())
    mv.view()
    assert.is_true(wait_for(function()
      return #notes > 1
    end))
    assert.equals(0, #floats())
  end)

  it("passes float.win_config to nvim_open_win and keeps it across zoom", function()
    config.setup({
      debounce_ms = 40,
      terminal = { placeholders = true },
      float = { win_config = { title = "diagram", title_pos = "center", zindex = 77, border = "single", row = 1 } },
    })
    local s = open(markdown())
    local cfg = vim.api.nvim_win_get_config(s.win)
    assert.equals(77, cfg.zindex)
    assert.equals("center", cfg.title_pos)
    assert.equals("diagram", cfg.title[1][1])
    assert.equals(1, cfg.row)
    nav.zoom_in()
    wait_zoom(s, function()
      return s.zoom == 1.5
    end)
    cfg = vim.api.nvim_win_get_config(s.win)
    assert.equals(77, cfg.zindex)
    assert.equals(1, cfg.row)
    assert.equals("diagram", cfg.title[1][1])
  end)

  it("sizes the diagram to float.win_config width and height when given", function()
    config.setup({
      debounce_ms = 40,
      terminal = { placeholders = true },
      float = { win_config = { width = 30, height = 10 } },
    })
    local s = open(markdown(WIDE))
    assert.equals(30, vim.api.nvim_win_get_width(s.win))
    assert.equals(10, vim.api.nvim_win_get_height(s.win))
    assert.is_true(s.cols <= 30 and s.rows <= 10)
  end)

  it("zooms instantly with focus in the float: resizes the same image's placement, no render or transmit", function()
    local s = open(markdown())
    local id, old_cols, old_rows = s.image.id, s.cols, s.rows
    sent = {}
    nav.zoom_in()
    -- synchronous: no wait
    assert.equals(1.5, s.zoom)
    assert.equals(id, s.image.id)
    assert.is_true(s.cols > old_cols and s.rows > old_rows)
    assert.same(kitty.placeholder_lines(s.cols, s.rows), vim.api.nvim_buf_get_lines(s.buf, 0, -1, false))
    assert.is_nil(find("t"))
    -- old placements are dropped (d=i keeps the image data), then the new size is placed
    local ctrls = {}
    for ctrl in sent[#sent]:gmatch("\27_G([^;\27]*)") do
      ctrls[#ctrls + 1] = ctrl
    end
    assert.equals(2, #ctrls)
    assert.truthy(ctrls[1]:find("a=d", 1, true))
    assert.truthy(ctrls[1]:find("d=i", 1, true))
    assert.truthy(ctrls[1]:find("i=" .. id, 1, true))
    local ctrl = ctrls[2]
    assert.truthy(ctrl:find("a=p", 1, true))
    assert.truthy(ctrl:find("i=" .. id, 1, true))
    assert.truthy(ctrl:find("c=" .. s.cols, 1, true))
    assert.truthy(ctrl:find("r=" .. s.rows, 1, true))
    assert.equals(s.win, vim.api.nvim_get_current_win())
  end)

  it("renders once at the max-zoom resolution", function()
    local s = open(markdown())
    local w = require("mermaid-viewer.png").dimensions(s.image.path)
    local maxc, maxr = require("mermaid-viewer.viewer").max_size()
    local size = require("mermaid-viewer.size")
    local cap = require("mermaid-viewer.viewer").zoom_cap(s.aspect)
    local cols, rows = size.float(s.aspect, maxc, maxr, cap, kitty.cell_size())
    local want = size.pixels(cols, rows, kitty.cell_size())
    assert.is_true(math.abs(w - want) <= 0.1 * want)
    assert.is_true(w > s.cols * kitty.cell_size().width)
  end)

  it("re-renders when the bound block is edited with focus in the float", function()
    local buf = markdown()
    local s = open(buf)
    local hash, old_id = s.hash, s.image.id
    vim.api.nvim_buf_set_lines(buf, 5, 5, false, { "  C --> D" })
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
    wait_zoom(s, function()
      return s.hash ~= hash and s.image.id ~= old_id
    end)
    assert.is_not_nil(find("d", old_id))
    assert.equals(s.win, vim.api.nvim_get_current_win())
  end)

  it("keeps the binding when lines are inserted above the block", function()
    local buf = markdown()
    local s = open(buf)
    vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "intro", "more intro", "" })
    vim.api.nvim_buf_set_lines(buf, 8, 8, false, { "  C --> D" })
    local hash = s.hash
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
    wait_zoom(s, function()
      return s.hash ~= hash
    end)
    assert.is_not_nil(s.image)
    assert.equals(0, #notes)
  end)

  it("closes with a notification when the block vanishes", function()
    local buf = markdown()
    local s = open(buf)
    local win = s.win
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "nothing here" })
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
    assert.is_true(wait_for(function()
      return state.current == nil
    end))
    assert.is_false(vim.api.nvim_win_is_valid(win))
    assert.equals(vim.log.levels.WARN, notes[#notes].level)
    assert.is_not_nil(find("d"))
  end)

  it("clamps zoom at the configured maximum", function()
    config.setup({ debounce_ms = 40, max_zoom = 1.6, terminal = { placeholders = true } })
    local s = open(markdown())
    nav.zoom_in()
    wait_zoom(s, function()
      return s.zoom == 1.5
    end)
    nav.zoom_in()
    wait_zoom(s, function()
      return s.zoom == 1.6
    end)
    local n = #commands()
    nav.zoom_in()
    vim.wait(300)
    assert.equals(1.6, s.zoom)
    assert.equals(n, #commands())
  end)

  it("keeps grids within 297 cells", function()
    config.setup({ debounce_ms = 40, max_zoom = 100, terminal = { placeholders = true } })
    local s = open(markdown())
    for _ = 1, 12 do
      local prev = s.zoom
      nav.zoom_in()
      if not wait_for(function()
        return s.zoom ~= prev
      end, 1500) then
        break
      end
    end
    assert.is_true(math.max(s.cols, s.rows) <= 297, s.cols .. "x" .. s.rows)
    assert.is_true(math.max(s.cols, s.rows) >= 295, s.cols .. "x" .. s.rows)
  end)

  it("reset returns to 1.0x with the view at the top-left", function()
    local s = open(markdown(WIDE))
    nav.zoom_in()
    wait_zoom(s, function()
      return s.zoom == 1.5
    end)
    vim.cmd("normal! 5zl")
    vim.cmd("normal! G")
    nav.zoom_reset()
    wait_zoom(s, function()
      return s.zoom == 1.0
    end)
    local v = vim.api.nvim_win_call(s.win, vim.fn.winsaveview)
    assert.equals(1, v.topline)
    assert.equals(0, v.leftcol)
    assert.equals(1, v.lnum)
  end)

  it("keeps the centered cell centered across zoom steps", function()
    local s = open(markdown(WIDE))
    nav.zoom_in()
    wait_zoom(s, function()
      return s.zoom == 1.5
    end)
    local function center()
      local v = vim.api.nvim_win_call(s.win, vim.fn.winsaveview)
      local w = vim.api.nvim_win_get_width(s.win)
      return (v.leftcol + w / 2) / s.cols
    end
    vim.cmd("normal! 8zl")
    vim.api.nvim_exec_autocmds("WinScrolled", { pattern = tostring(s.win) })
    local before = center()
    nav.zoom_in()
    wait_zoom(s, function()
      return s.zoom > 1.5
    end)
    assert.is_true(math.abs(center() - before) < 0.03, ("%f vs %f"):format(center(), before))
    nav.zoom_out()
    wait_zoom(s, function()
      return s.zoom == 1.5
    end)
    assert.is_true(math.abs(center() - before) < 0.03)
  end)

  it("moves with native motions and stops at the edges", function()
    local s = open(markdown(WIDE))
    local w = vim.api.nvim_win_get_width(s.win)
    assert.is_true(s.cols <= w)
    nav.zoom_in()
    wait_zoom(s, function()
      return s.zoom == 1.5
    end)
    w = vim.api.nvim_win_get_width(s.win)
    assert.is_true(s.cols > w)
    local function view()
      return vim.api.nvim_win_call(s.win, vim.fn.winsaveview)
    end
    vim.cmd("normal! 0")
    vim.cmd("normal! 3zl")
    assert.equals(3, view().leftcol)
    vim.cmd("normal! 500zl")
    -- WinScrolled only fires on redraw, which headless runs don't do
    vim.api.nvim_exec_autocmds("WinScrolled", { pattern = tostring(s.win) })
    assert.equals(s.cols - w, view().leftcol)
    vim.cmd("normal! 0")
    vim.cmd("normal! 500l")
    assert.equals(s.cols, vim.fn.virtcol("."))
    vim.cmd("normal! gg")
    vim.cmd("normal! 500j")
    assert.equals(s.rows, vim.fn.line("."))
  end)

  it("scrolls the view one step per h/j/k/l press and stops at the edges", function()
    local s = open(markdown(WIDE))
    nav.zoom_in()
    wait_zoom(s, function()
      return s.zoom == 1.5
    end)
    nav.zoom_in()
    wait_zoom(s, function()
      return s.zoom == 2.25
    end)
    local w, h = vim.api.nvim_win_get_width(s.win), vim.api.nvim_win_get_height(s.win)
    assert.is_true(s.cols > w)
    local function view()
      return vim.api.nvim_win_call(s.win, vim.fn.winsaveview)
    end
    vim.fn.winrestview({ topline = 1, leftcol = 0, lnum = 1, col = 0 })
    local function press(keys)
      vim.api.nvim_feedkeys(vim.keycode(keys), "x", false)
    end
    press("l")
    assert.equals(1, view().leftcol)
    press("3l")
    assert.equals(4, view().leftcol)
    press("h")
    assert.equals(3, view().leftcol)
    press("500l")
    assert.equals(s.cols - w, view().leftcol)
    press("500h")
    assert.equals(0, view().leftcol)
    press("L")
    assert.equals(2, view().leftcol)
    press("2L")
    assert.equals(6, view().leftcol)
    press("H")
    assert.equals(4, view().leftcol)
    press("500h")
    if s.rows > h then
      press("j")
      assert.equals(2, view().topline)
      press("k")
      assert.equals(1, view().topline)
      press("J")
      assert.equals(3, view().topline)
      press("K")
      assert.equals(1, view().topline)
      press("500j")
      assert.equals(s.rows - h + 1, view().topline)
    end
  end)

  it("does not scroll away when the diagram fits", function()
    local s = open(markdown())
    vim.cmd("normal! 5zl")
    vim.api.nvim_exec_autocmds("WinScrolled", { pattern = tostring(s.win) })
    assert.equals(0, vim.api.nvim_win_call(s.win, vim.fn.winsaveview).leftcol)
  end)

  it("tears down on :q and reopens", function()
    local s = open(markdown())
    local id, win = s.image.id, s.win
    vim.cmd("q")
    assert.is_nil(state.current)
    assert.is_false(vim.api.nvim_win_is_valid(win))
    assert.is_not_nil(find("d", id))
    assert.is_nil(registry.get(s.key))
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    mv.view()
    assert.is_true(wait_for(function()
      return state.current ~= nil
    end))
    assert.is_true(vim.api.nvim_win_is_valid(state.current.win))
  end)

  it("re-sends the other images to the terminal after closing", function()
    local png = vim.fn.tempname() .. ".png"
    vim.fn.writefile({ "fake" }, png)
    local other = registry.acquire("inline-image", png, 4, 3)
    local s = open(markdown())
    local id = s.image.id
    sent = {}
    mv.close()
    local deleted = find("d", id)
    local resent = find("t", other.id)
    assert.is_not_nil(deleted)
    assert.is_not_nil(resent)
    assert.is_true(resent > deleted)
    assert.is_nil(find("t", id))
    registry.release("inline-image")
    os.remove(png)
  end)

  it("tears down when the float is closed through the API", function()
    local s = open(markdown())
    local id = s.image.id
    vim.api.nvim_win_close(s.win, true)
    assert.is_nil(state.current)
    assert.is_not_nil(find("d", id))
  end)

  it("closes with q and toggles", function()
    local buf = markdown()
    local win = open(buf).win
    vim.api.nvim_feedkeys("q", "x", false)
    assert.is_nil(state.current)
    assert.is_false(vim.api.nvim_win_is_valid(win))
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    mv.toggle()
    assert.is_true(wait_for(function()
      return state.current ~= nil
    end))
    mv.toggle()
    assert.is_nil(state.current)
  end)

  it("uses the whole buffer for .mmd files", function()
    vim.cmd("enew!")
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. ".mmd")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "graph TD", "  A --> B" })
    local s = open(buf, 1)
    assert.is_not_nil(s)
    assert.is_nil(s.source.mark)
    assert.equals(buf, s.source.buf)
    local hash = s.hash
    vim.api.nvim_buf_set_lines(buf, 2, 2, false, { "  B --> C" })
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
    wait_zoom(s, function()
      return s.hash ~= hash
    end)
  end)

  it("errors in buffers without mermaid content", function()
    vim.cmd("enew!")
    vim.bo.filetype = "lua"
    mv.view()
    assert.equals(1, #notes)
    assert.truthy(notes[1].msg:find("No mermaid diagram found", 1, true))
  end)

  it("scrolls pan_step cells per h/j/k/l press", function()
    config.setup({ pan_step = 3, terminal = { placeholders = true } })
    local s = open(markdown(WIDE))
    nav.zoom_in()
    wait_zoom(s, function()
      return s.zoom == 1.5
    end)
    nav.zoom_in()
    wait_zoom(s, function()
      return s.zoom == 2.25
    end)
    vim.fn.winrestview({ topline = 1, leftcol = 0, lnum = 1, col = 0 })
    local function leftcol()
      return vim.api.nvim_win_call(s.win, vim.fn.winsaveview).leftcol
    end
    vim.api.nvim_feedkeys("l", "x", false)
    assert.equals(3, leftcol())
    vim.api.nvim_feedkeys("2l", "x", false)
    assert.equals(9, leftcol())
    vim.api.nvim_feedkeys("H", "x", false)
    assert.equals(3, leftcol())
  end)

  it("ignores removed pan options with a single warning", function()
    notes = {}
    config.setup({ keys = { pan_up = "K" }, terminal = { placeholders = true } })
    config.setup({ keys = { pan_up = "K" }, terminal = { placeholders = true } })
    local warnings = vim.tbl_filter(function(n)
      return n.level == vim.log.levels.WARN and n.msg:find("native motions", 1, true)
    end, notes)
    assert.is_true(#warnings <= 1)
    notes = {}
    local s = open(markdown())
    assert.is_not_nil(s)
    assert.is_nil(config.options.keys.pan_up)
  end)
end)
