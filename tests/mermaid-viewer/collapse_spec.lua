describe("mermaid-viewer.collapse", function()
  local config, inline, collapse, registry, kitty
  local inline_ns, collapse_ns
  local sent, orig_send, notified, orig_notify
  local bufs

  local BLOCK = { "```mermaid", "graph TD", "  A --> B", "  B --> C", "```" }
  -- rows: 0 intro, 1-5 block, 6 after
  local LINES = { "intro", unpack(BLOCK) }
  LINES[#LINES + 1] = "after"

  before_each(function()
    vim.o.termguicolors = true
    for k in pairs(package.loaded) do
      if k:match("^mermaid%-viewer") then
        package.loaded[k] = nil
      end
    end
    config = require("mermaid-viewer.config")
    kitty = require("mermaid-viewer.kitty")
    registry = require("mermaid-viewer.registry")
    collapse = require("mermaid-viewer.collapse")
    inline = require("mermaid-viewer.inline")
    config.setup({ debounce_ms = 30, terminal = { placeholders = true }, inline = { max_height = 6 } })
    inline_ns = vim.api.nvim_create_namespace("mermaid_viewer_inline")
    collapse_ns = vim.api.nvim_create_namespace("mermaid_viewer_collapse")
    kitty.cell_size = function()
      return { width = 10, height = 20 }
    end
    registry._reset(9000)
    sent, notified = {}, {}
    orig_send = vim.api.nvim_ui_send
    vim.api.nvim_ui_send = function(data)
      sent[#sent + 1] = data
    end
    orig_notify = vim.notify
    vim.notify = function(msg, level)
      notified[#notified + 1] = { msg = msg, level = level }
    end
    bufs = {}
  end)

  after_each(function()
    pcall(inline._reset)
    pcall(collapse._reset)
    for _, b in ipairs(bufs) do
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
    vim.cmd("only")
    vim.wo.conceallevel = 0
    vim.api.nvim_ui_send = orig_send
    vim.notify = orig_notify
  end)

  local function make_buf(lines)
    local b = vim.api.nvim_create_buf(true, false)
    bufs[#bufs + 1] = b
    vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
    vim.bo[b].filetype = "markdown"
    vim.api.nvim_win_set_buf(0, b)
    vim.cmd("redraw")
    return b
  end

  local function wait_for(cond, msg)
    assert.is_true(vim.wait(15000, cond, 20), msg or "timed out")
  end

  local function diagram_mark(b)
    return vim.api.nvim_buf_get_extmarks(b, inline_ns, 0, -1, { details = true })[1]
  end

  local function conceal_marks(b)
    return vim.api.nvim_buf_get_extmarks(b, collapse_ns, 0, -1, { details = true })
  end

  local function rendered(b)
    local m = diagram_mark(b)
    return m ~= nil and #m[4].virt_lines >= config.options.inline.max_height
  end

  --- text of the screen rows of the current window
  local function screen()
    vim.cmd("redraw")
    local rows = {}
    for r = 1, vim.api.nvim_win_get_height(0) do
      local t = {}
      for c = 1, 30 do
        t[#t + 1] = vim.fn.screenstring(r, c)
      end
      rows[#rows + 1] = table.concat(t)
    end
    return table.concat(rows, "\n")
  end

  local function setup_collapsed()
    local b = make_buf(LINES)
    inline.enable(b)
    wait_for(function()
      return rendered(b)
    end, "diagram rendered")
    assert.is_true(collapse.toggle(b, 3))
    return b
  end

  describe("toggle (6.1)", function()
    it("hides the whole block range and shows a marker with the line count", function()
      local b = setup_collapsed()
      local c = conceal_marks(b)
      assert.equals(1, #c)
      assert.equals(1, c[1][2])
      assert.equals(5, c[1][4].end_row)
      assert.equals("", c[1][4].conceal_lines)

      local m = diagram_mark(b)
      local d = m[4]
      local img_rows = config.options.inline.max_height
      assert.equals(img_rows + 1, #d.virt_lines)
      assert.equals("··· 5 lines (mermaid)", d.virt_lines[#d.virt_lines][1][1])
      -- hangs from the first visible row after the block, still above it
      assert.equals(6, m[2])
      assert.is_true(d.virt_lines_above)
      assert.truthy(d.virt_lines[1][1][1]:find(vim.fn.nr2char(0x10EEEE), 1, true))

      local id = inline.block_at(b, 3)
      assert.is_true(collapse.is_collapsed(b, id))
    end)

    it("makes the source disappear from the screen and sets conceallevel", function()
      local b = make_buf(LINES)
      assert.equals(0, vim.wo.conceallevel)
      inline.enable(b)
      wait_for(function()
        return rendered(b)
      end)
      assert.truthy(screen():find("graph TD", 1, true))
      collapse.toggle(b, 1)
      assert.equals(2, vim.wo.conceallevel)
      local s = screen()
      assert.is_nil(s:find("graph TD", 1, true))
      assert.is_nil(s:find("A --> B", 1, true))
      assert.truthy(s:find("··· 5 lines (mermaid)", 1, true))
      assert.truthy(s:find("after", 1, true))
      collapse.toggle(b, 1)
      assert.equals(0, vim.wo.conceallevel)
      assert.truthy(screen():find("graph TD", 1, true))
    end)

    it("keeps the source hidden when the cursor rests on it in normal mode", function()
      local b = make_buf(LINES)
      inline.enable(b)
      wait_for(function()
        return rendered(b)
      end)
      collapse.toggle(b, 1)
      vim.api.nvim_win_set_cursor(0, { 4, 0 })
      assert.is_nil(screen():find("A --> B", 1, true))
      vim.api.nvim_win_set_cursor(0, { 6, 0 })
      assert.is_nil(screen():find("A --> B", 1, true))
    end)

    it("leaves conceallevel alone when it is already set, and restores concealcursor", function()
      vim.wo.conceallevel = 3
      vim.wo.concealcursor = ""
      local b = make_buf(LINES)
      inline.enable(b)
      wait_for(function()
        return rendered(b)
      end)
      collapse.toggle(b, 1)
      assert.equals(3, vim.wo.conceallevel)
      assert.truthy(vim.wo.concealcursor:find("n", 1, true))
      collapse.toggle(b, 1)
      assert.equals(3, vim.wo.conceallevel)
      assert.equals("", vim.wo.concealcursor)
    end)

    it("expands again with the same toggle and restores the diagram above the fence", function()
      local b = setup_collapsed()
      assert.is_true(collapse.toggle(b, 3))
      assert.equals(0, #conceal_marks(b))
      local m = diagram_mark(b)
      assert.equals(1, m[2])
      assert.equals(config.options.inline.max_height, #m[4].virt_lines)
      assert.is_false(collapse.is_collapsed(b, inline.block_at(b, 3)))
    end)

    it("toggles from the fences, the row the diagram hangs from, and not from other rows", function()
      local b = setup_collapsed()
      -- block_at covers the collapsed block's rows and its attach row
      local id = inline.block_at(b, 1)
      assert.is_number(id)
      assert.equals(id, inline.block_at(b, 5)) -- closing fence
      assert.equals(id, inline.block_at(b, 6)) -- the row the diagram and marker hang from
      assert.is_nil(inline.block_at(b, 0))
      assert.is_nil(inline.block_at(b, 7))

      assert.is_true(collapse.toggle(b, 6))
      assert.is_false(collapse.is_collapsed(b, id))
      assert.is_nil(inline.block_at(b, 6)) -- expanded: the row after the block is no longer on it
      assert.is_true(collapse.toggle(b, 1)) -- opening fence
      assert.is_true(collapse.is_collapsed(b, id))
      assert.is_true(collapse.toggle(b, 6))
    end)

    it("notifies when there is no block at the row", function()
      local b = make_buf(LINES)
      inline.enable(b)
      assert.is_false(collapse.toggle(b, 0))
      assert.equals("No mermaid diagram found at cursor", notified[#notified].msg)
      assert.equals(vim.log.levels.ERROR, notified[#notified].level)
    end)

    it("hangs the diagram below the previous row when the block ends the buffer", function()
      local b = make_buf({ "intro", unpack(BLOCK) })
      inline.enable(b)
      wait_for(function()
        return rendered(b)
      end)
      collapse.toggle(b, 2)
      local m = diagram_mark(b)
      assert.equals(0, m[2])
      assert.is_falsy(m[4].virt_lines_above)
      assert.equals("··· 5 lines (mermaid)", m[4].virt_lines[#m[4].virt_lines][1][1])
      assert.equals(1, #conceal_marks(b))
    end)

    it("moves past another collapsed block directly after it", function()
      local b = make_buf({ unpack(BLOCK) })
      vim.api.nvim_buf_set_lines(b, -1, -1, false, { unpack(BLOCK) })
      vim.api.nvim_buf_set_lines(b, -1, -1, false, { "tail" })
      inline.enable(b)
      wait_for(function()
        return #vim.api.nvim_buf_get_extmarks(b, inline_ns, 0, -1, {}) == 2
      end)
      collapse.toggle(b, 0)
      collapse.toggle(b, 5)
      local rows = {}
      for _, m in ipairs(vim.api.nvim_buf_get_extmarks(b, inline_ns, 0, -1, {})) do
        rows[#rows + 1] = m[2]
      end
      -- both diagrams hang from "tail" (row 10)
      assert.same({ 10, 10 }, rows)
    end)

    it("is removed together with the diagrams when inline rendering is turned off", function()
      local b = setup_collapsed()
      inline.disable(b)
      assert.equals(0, #conceal_marks(b))
      assert.equals(0, #vim.api.nvim_buf_get_extmarks(b, inline_ns, 0, -1, {}))
      assert.equals(0, vim.wo.conceallevel)
      assert.truthy(screen():find("graph TD", 1, true))
      assert.is_nil(inline.block_at(b, 3))
    end)

    it("refuses to collapse while inline rendering is off", function()
      local b = make_buf(LINES)
      assert.is_false(collapse.toggle(b, 2))
      assert.equals(0, #conceal_marks(b))
    end)

    it("updates the marker count and range after edits", function()
      local b = setup_collapsed()
      vim.api.nvim_buf_set_lines(b, 0, 0, false, { "new1", "new2" })
      inline.refresh(b)
      local c = conceal_marks(b)
      assert.equals(3, c[1][2])
      assert.equals(7, c[1][4].end_row)
      assert.equals(8, diagram_mark(b)[2])
    end)
  end)

  describe("temporary expansion (6.2)", function()
    it("expands when an editing mode starts on the block and collapses after leaving it", function()
      local b = setup_collapsed()
      local id = inline.block_at(b, 3)
      vim.api.nvim_win_set_cursor(0, { 4, 0 })

      collapse.on_mode(b, "i")
      assert.is_true(collapse.is_collapsed(b, id))
      assert.is_false(collapse.is_hidden(b, id))
      assert.equals(0, #conceal_marks(b))
      assert.equals(1, diagram_mark(b)[2])
      assert.truthy(screen():find("A --> B", 1, true))

      -- back to normal mode with the cursor still inside: stays open
      collapse.on_mode(b, "n")
      assert.is_false(collapse.is_hidden(b, id))

      -- cursor leaves in normal mode: collapsed again
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      collapse.on_mode(b, "n")
      assert.is_true(collapse.is_hidden(b, id))
      assert.equals(1, #conceal_marks(b))
      assert.is_nil(screen():find("A --> B", 1, true))
    end)

    it("expands for visual mode and for insert mode started on the marker row", function()
      local b = setup_collapsed()
      local id = inline.block_at(b, 3)
      vim.api.nvim_win_set_cursor(0, { 7, 0 }) -- the row the marker hangs from
      collapse.on_mode(b, "v")
      assert.is_false(collapse.is_hidden(b, id))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      collapse.on_mode(b, "n")
      assert.is_true(collapse.is_hidden(b, id))
    end)

    it("stays collapsed while moving across the block in normal mode", function()
      local b = setup_collapsed()
      local id = inline.block_at(b, 3)
      for _, line in ipairs({ 1, 2, 3, 4, 5, 6, 7, 5, 2 }) do
        vim.api.nvim_win_set_cursor(0, { line, 0 })
        vim.api.nvim_exec_autocmds("CursorMoved", { buffer = b })
        assert.is_true(collapse.is_hidden(b, id), "line " .. line)
      end
      assert.equals(1, #conceal_marks(b))
    end)

    it("works through the real ModeChanged and CursorMoved autocmds", function()
      local b = setup_collapsed()
      local id = inline.block_at(b, 3)
      vim.api.nvim_win_set_cursor(0, { 4, 0 })
      vim.api.nvim_feedkeys("i", "tx", false)
      -- insert mode was entered and left again on the block: it is still open
      assert.is_false(collapse.is_hidden(b, id))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      vim.api.nvim_exec_autocmds("CursorMoved", { buffer = b })
      assert.is_true(collapse.is_hidden(b, id))

      vim.api.nvim_win_set_cursor(0, { 3, 0 })
      vim.api.nvim_feedkeys("v", "tx", false)
      assert.is_false(collapse.is_hidden(b, id))
      vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "tx", false)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      vim.api.nvim_exec_autocmds("CursorMoved", { buffer = b })
      assert.is_true(collapse.is_hidden(b, id))
    end)

    it("a plain toggle while temporarily expanded collapses it for good", function()
      local b = setup_collapsed()
      local id = inline.block_at(b, 3)
      vim.api.nvim_win_set_cursor(0, { 4, 0 })
      collapse.on_mode(b, "i")
      assert.is_true(collapse.toggle(b, 3))
      assert.is_true(collapse.is_hidden(b, id))
      assert.equals(1, #conceal_marks(b))
    end)
  end)
end)
