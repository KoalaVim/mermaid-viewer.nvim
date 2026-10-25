describe("mermaid-viewer.inline", function()
  local config, inline, registry, kitty, blocks
  local ns
  local sent, orig_send, orig_cell, orig_notify, notified
  local bufs
  local saved_env

  local TALL = { "```mermaid", "graph TD", "  A --> B", "  B --> C", "  C --> D", "```" }
  local OTHER = { "```mermaid", "graph TD", "  X --> Y", "  Y --> Z", "  Z --> W", "```" }

  local function reload()
    for k in pairs(package.loaded) do
      if k:match("^mermaid%-viewer") then
        package.loaded[k] = nil
      end
    end
    config = require("mermaid-viewer.config")
    kitty = require("mermaid-viewer.kitty")
    registry = require("mermaid-viewer.registry")
    blocks = require("mermaid-viewer.blocks")
    inline = require("mermaid-viewer.inline")
  end

  before_each(function()
    saved_env = { TERM_PROGRAM = vim.env.TERM_PROGRAM }
    vim.o.termguicolors = true
    reload()
    config.setup({ debounce_ms = 30, terminal = { placeholders = true }, inline = { max_height = 6, collapse = false } })
    ns = vim.api.nvim_create_namespace("mermaid_viewer_inline")
    kitty.cell_size = function()
      return { width = 10, height = 20 }
    end
    registry._reset(5000)
    sent = {}
    orig_send = vim.api.nvim_ui_send
    vim.api.nvim_ui_send = function(data)
      sent[#sent + 1] = data
    end
    notified = {}
    orig_notify = vim.notify
    vim.notify = function(msg, level)
      notified[#notified + 1] = { msg = msg, level = level }
    end
    bufs = {}
  end)

  after_each(function()
    pcall(inline._reset)
    pcall(require("mermaid-viewer.collapse")._reset)
    for _, b in ipairs(bufs) do
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
    vim.cmd("only")
    vim.api.nvim_ui_send = orig_send
    vim.notify = orig_notify
    vim.env.TERM_PROGRAM = saved_env.TERM_PROGRAM
  end)

  ---@param lines string[]
  ---@param opts? { ft?: string, split?: boolean }
  local function make_buf(lines, opts)
    opts = opts or {}
    local b = vim.api.nvim_create_buf(true, false)
    bufs[#bufs + 1] = b
    vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
    vim.bo[b].filetype = opts.ft or "markdown"
    if opts.split then
      vim.cmd("vsplit")
    end
    vim.api.nvim_win_set_buf(0, b)
    vim.cmd("redraw")
    return b
  end

  local function concat(...)
    local out = {}
    for _, t in ipairs({ ... }) do
      vim.list_extend(out, t)
    end
    return out
  end

  local function marks(b)
    return vim.api.nvim_buf_get_extmarks(b, ns, 0, -1, { details = true })
  end

  local function wait_for(cond, msg)
    local ok = vim.wait(15000, cond, 20)
    assert.is_true(ok, msg or "timed out")
  end

  local function sent_matching(pat)
    local n = 0
    for _, s in ipairs(sent) do
      if s:find(pat, 1, true) then
        n = n + 1
      end
    end
    return n
  end

  local function first_index(pat)
    for i, s in ipairs(sent) do
      if s:find(pat, 1, true) then
        return i
      end
    end
  end

  local PLACEHOLDER = vim.fn.nr2char(0x10EEEE)

  describe("rendering (5.1)", function()
    it("renders each mermaid block above its fence and ignores other languages", function()
      local lines = concat({ "# T" }, TALL, { "text" }, { "```lua", "print(1)", "```" }, { "" }, OTHER)
      local b = make_buf(lines)
      assert.is_true(inline.enable(b))
      wait_for(function()
        return #marks(b) == 2
      end, "two diagrams")

      local m = marks(b)
      assert.equals(1, m[1][2])
      assert.equals(12, m[2][2])
      for _, mark in ipairs(m) do
        local d = mark[4]
        assert.is_true(d.virt_lines_above)
        assert.equals(config.options.inline.max_height, #d.virt_lines)
        local chunk = d.virt_lines[1][1]
        assert.equals(PLACEHOLDER, chunk[1]:sub(1, #PLACEHOLDER))
        assert.is_truthy(chunk[2]:match("^MermaidViewerImage%d+$"))
      end
      -- not a single mark on the lua block (rows 8-10)
      for _, mark in ipairs(m) do
        assert.is_false(mark[2] >= 8 and mark[2] <= 10)
      end
      -- the buffer text is untouched
      assert.same(lines, vim.api.nvim_buf_get_lines(b, 0, -1, false))
    end)

    it("transmits and places each image once", function()
      local b = make_buf(concat(TALL, { "" }, OTHER))
      inline.enable(b)
      wait_for(function()
        return #marks(b) == 2
      end)
      assert.equals(2, sent_matching("a=t"))
      assert.equals(2, sent_matching("U=1"))
    end)

    it("transmits the same source again when it is shown at a different grid size", function()
      local wide = { "```mermaid", "graph LR" }
      for i = 1, 5 do
        wide[#wide + 1] = ("  N%d --> N%d"):format(i, i + 1)
      end
      wide[#wide + 1] = "```"
      local a = make_buf(wide)
      local b = make_buf(wide, { split = true })
      vim.cmd("vertical resize 30")
      inline.enable(a)
      inline.enable(b)
      wait_for(function()
        return #marks(a) == 1 and #marks(b) == 1
      end)
      assert.is_true(#marks(a)[1][4].virt_lines ~= #marks(b)[1][4].virt_lines)
      assert.equals(2, sent_matching("a=t"))
      assert.is_not.equals(marks(a)[1][4].virt_lines[1][1][2], marks(b)[1][4].virt_lines[1][1][2])
    end)

    it("renders only blocks near the visible range, and the rest once scrolled into view", function()
      local filler = {}
      for i = 1, 120 do
        filler[i] = "line " .. i
      end
      local b = make_buf(concat(TALL, filler, OTHER))
      inline.enable(b)
      wait_for(function()
        return #marks(b) == 1
      end)
      -- give a stray render a chance to show up
      vim.wait(300)
      assert.equals(1, #marks(b))
      assert.equals(0, marks(b)[1][2])

      vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(b), 0 })
      vim.cmd("redraw")
      vim.api.nvim_exec_autocmds("WinScrolled", {})
      wait_for(function()
        return #marks(b) == 2
      end, "far block rendered after scrolling")

      -- scrolling back neither re-renders nor re-transmits
      local before = #sent
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      vim.cmd("redraw")
      vim.api.nvim_exec_autocmds("WinScrolled", {})
      vim.wait(200)
      assert.equals(before, #sent)
    end)

    it("sizes wide diagrams down to the window text width", function()
      local wide = { "```mermaid", "graph LR" }
      for i = 1, 5 do
        wide[#wide + 1] = ("  N%d --> N%d"):format(i, i + 1)
      end
      wide[#wide + 1] = "```"
      local b = make_buf(wide)
      vim.cmd("vertical resize 30")
      inline.enable(b)
      wait_for(function()
        return #marks(b) == 1
      end)
      local d = marks(b)[1][4]
      assert.truthy(d.virt_lines[1][1][2]:match("^MermaidViewerImage"))
      assert.is_true(#d.virt_lines < config.options.inline.max_height)
      local info = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
      local cells = vim.fn.strchars(d.virt_lines[1][1][1]) / 3
      assert.is_true(cells <= info.width - info.textoff)
    end)
  end)

  describe("edits (5.2)", function()
    it("transmits the new image before deleting the old, and leaves other blocks alone", function()
      local b = make_buf(concat(TALL, { "" }, OTHER))
      inline.enable(b)
      wait_for(function()
        return #marks(b) == 2
      end)
      local before = #sent
      local old_mark = marks(b)[1]
      local old_hl = old_mark[4].virt_lines[1][1][2]

      vim.api.nvim_buf_set_lines(b, 3, 4, false, { "  B --> E" })
      vim.api.nvim_exec_autocmds("TextChanged", { buffer = b })
      wait_for(function()
        return sent_matching("d=I") >= 1
      end, "old image deleted")
      vim.wait(100)

      local after = {}
      for i = before + 1, #sent do
        after[#after + 1] = sent[i]
      end
      assert.equals(2, #after, "one transmit + one delete")
      assert.truthy(after[1]:find("a=t", 1, true))
      assert.truthy(after[2]:find("a=d", 1, true))

      local m = marks(b)
      assert.equals(2, #m)
      assert.equals(old_mark[1], m[1][1])
      assert.is_not.equals(old_hl, m[1][4].virt_lines[1][1][2])
      assert.equals(config.options.inline.max_height, #m[1][4].virt_lines)
    end)

    it("shows the diagram of a new block after the debounce", function()
      local b = make_buf(concat({ "intro" }, TALL))
      inline.enable(b)
      wait_for(function()
        return #marks(b) == 1
      end)
      vim.api.nvim_buf_set_lines(b, -1, -1, false, concat({ "" }, OTHER))
      vim.api.nvim_exec_autocmds("TextChanged", { buffer = b })
      wait_for(function()
        return #marks(b) == 2
      end)
    end)

    it("drops the diagram when the block is removed", function()
      local b = make_buf(concat(TALL, { "" }, OTHER))
      inline.enable(b)
      wait_for(function()
        return #marks(b) == 2
      end)
      vim.api.nvim_buf_set_lines(b, 0, 6, false, {})
      vim.api.nvim_exec_autocmds("TextChanged", { buffer = b })
      wait_for(function()
        return #marks(b) == 1 and sent_matching("d=I") == 1
      end)
    end)
  end)

  describe("errors (5.3)", function()
    it("shows one error line, then the diagram once fixed, without notifications", function()
      local b = make_buf({ "```mermaid", "graph TD", "  A -->", "```" })
      inline.enable(b)
      wait_for(function()
        return #marks(b) == 1
      end)
      local d = marks(b)[1][4]
      assert.equals(1, #d.virt_lines)
      assert.is_true(d.virt_lines_above)
      assert.equals(0, marks(b)[1][2])
      local text, hl = d.virt_lines[1][1][1], d.virt_lines[1][1][2]
      assert.equals("DiagnosticError", hl)
      assert.truthy(text:find("invalid flowchart edge syntax", 1, true))
      assert.equals(0, #sent)

      vim.api.nvim_buf_set_lines(b, 2, 3, false, { "  A --> B", "  B --> C" })
      vim.api.nvim_exec_autocmds("TextChanged", { buffer = b })
      wait_for(function()
        return #marks(b) == 1 and #marks(b)[1][4].virt_lines > 1
      end, "diagram replaces the error")
      assert.equals(0, #notified)
    end)

    it("truncates the error to the window width", function()
      local b = make_buf({ "```mermaid", "graph TD", "  A -->", "```" }, { split = true })
      vim.cmd("vertical resize 20")
      inline.enable(b)
      wait_for(function()
        return #marks(b) == 1
      end)
      local text = marks(b)[1][4].virt_lines[1][1][1]
      local info = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
      assert.is_true(vim.fn.strdisplaywidth(text) <= info.width - info.textoff)
      assert.equals("…", vim.fn.strcharpart(text, vim.fn.strchars(text) - 1))
    end)

    it("does not re-render an unchanged failing block on every scroll", function()
      local b = make_buf({ "```mermaid", "graph TD", "  A -->", "```" })
      local calls = 0
      local render = require("mermaid-viewer.render")
      local orig = render.diagram
      render.diagram = function(...)
        calls = calls + 1
        return orig(...)
      end
      inline.enable(b)
      wait_for(function()
        return #marks(b) == 1
      end)
      vim.api.nvim_exec_autocmds("WinScrolled", {})
      vim.api.nvim_exec_autocmds("WinScrolled", {})
      vim.wait(100)
      render.diagram = orig
      assert.equals(1, calls)
    end)
  end)

  describe("toggle and config (5.4)", function()
    it("disable clears and releases only its own buffer; enable restores", function()
      local a = make_buf(TALL)
      local b = make_buf(OTHER, { split = true })
      inline.enable(a)
      inline.enable(b)
      wait_for(function()
        return #marks(a) == 1 and #marks(b) == 1
      end)
      assert.equals(0, sent_matching("d=I"))

      inline.disable(a)
      assert.is_false(inline.is_enabled(a))
      assert.is_true(inline.is_enabled(b))
      assert.equals(0, #marks(a))
      assert.equals(1, #marks(b))
      assert.equals(1, sent_matching("d=I"))

      inline.enable(a)
      wait_for(function()
        return #marks(a) == 1
      end)
      assert.equals(1, #marks(b))
    end)

    it("toggle flips the state and refuses non-markdown buffers", function()
      local b = make_buf(TALL)
      assert.is_true(inline.toggle(b))
      assert.is_true(inline.is_enabled(b))
      assert.is_false(inline.toggle(b))
      assert.is_false(inline.is_enabled(b))

      local lua = make_buf({ "print(1)" }, { ft = "lua" })
      inline.toggle(lua)
      assert.is_false(inline.is_enabled(lua))
      assert.equals(
        "inline rendering applies to markdown, mermaid and agent terminal buffers only",
        notified[#notified].msg
      )
    end)

    it("max_height config caps the diagram rows", function()
      config.options.inline.max_height = 4
      local b = make_buf(TALL)
      inline.enable(b)
      wait_for(function()
        return #marks(b) == 1
      end)
      assert.equals(4, #marks(b)[1][4].virt_lines)
    end)

    it("setup() auto-enables markdown buffers on FileType/BufWinEnter", function()
      inline.setup()
      local b = vim.api.nvim_create_buf(true, false)
      bufs[#bufs + 1] = b
      vim.api.nvim_buf_set_lines(b, 0, -1, false, TALL)
      vim.api.nvim_win_set_buf(0, b)
      vim.bo[b].filetype = "markdown"
      assert.is_true(inline.is_enabled(b))
      wait_for(function()
        return #marks(b) == 1
      end)
      -- a buffer the user switched off stays off when re-entered
      inline.toggle(b)
      vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = b })
      assert.is_false(inline.is_enabled(b))
    end)

    it("setup() is idempotent and does not auto-enable when inline.enabled = false", function()
      config.options.inline.enabled = false
      inline.setup()
      inline.setup()
      local b = make_buf(TALL)
      vim.api.nvim_exec_autocmds("FileType", { buffer = b })
      vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = b })
      assert.is_false(inline.is_enabled(b))
      assert.is_true(inline.toggle(b))
    end)

    it("does nothing on unsupported terminals", function()
      config.options.terminal.placeholders = false
      local b = make_buf(TALL)
      assert.is_false(inline.enable(b))
      assert.equals(0, #sent)
    end)

    it("wiping the buffer releases its images", function()
      local b = make_buf(TALL)
      inline.enable(b)
      wait_for(function()
        return #marks(b) == 1
      end)
      vim.api.nvim_buf_delete(b, { force = true })
      assert.equals(1, sent_matching("d=I"))
    end)
  end)

  describe("mermaid buffers and agent terminals", function()
    it("draws a mermaid buffer's diagram under its last line, and never collapses it", function()
      config.setup({ debounce_ms = 30, terminal = { placeholders = true }, inline = { max_height = 6 } })
      local b = make_buf({ "graph TD", "  A --> B", "  B --> C" }, { ft = "mermaid" })
      assert.is_true(inline.enable(b))
      wait_for(function()
        return #marks(b) == 1 and #marks(b)[1][4].virt_lines > 1
      end, "diagram")
      local m = marks(b)[1]
      assert.equals(2, m[2])
      assert.is_false(m[4].virt_lines_above)
      assert.is_false(require("mermaid-viewer.collapse").is_hidden(b, m[1]))
      assert.is_false(require("mermaid-viewer.collapse").toggle(b, 0))
      assert.equals("mermaid-viewer: collapse applies to markdown blocks only", notified[#notified].msg)
    end)

    it("draws each diagram of an agent terminal under it, and nothing for one that fails", function()
      local b = make_buf({
        "  flowchart TD",
        "      A --> B",
        "  text",
        "  graph TD",
        "      A -->",
        "  more",
      }, { ft = "sidekick_terminal" })
      assert.is_true(inline.enable(b))
      wait_for(function()
        return #marks(b) == 1
      end, "diagram")
      vim.wait(300)
      local m = marks(b)
      assert.equals(1, #m)
      assert.equals(1, m[1][2])
      assert.is_false(m[1][4].virt_lines_above)
      assert.equals(0, #notified)
    end)

    it("renders a terminal diagram once it is scrolled into view", function()
      local lines = { "  flowchart TD", "      A --> B" }
      for n = 1, 1000 do
        lines[#lines + 1] = "  prose " .. n
      end
      local b = make_buf(lines, { ft = "sidekick_terminal" })
      vim.api.nvim_win_set_cursor(0, { #lines, 0 })
      vim.cmd("redraw")
      assert.is_true(inline.enable(b))
      vim.wait(300)
      assert.equals(0, #marks(b))
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      vim.cmd("normal! zt")
      vim.api.nvim_exec_autocmds("WinScrolled", {})
      wait_for(function()
        return #marks(b) == 1
      end, "diagram after scrolling back")
      assert.equals(1, marks(b)[1][2])
    end)

    it("follows output of a real terminal buffer", function()
      local b = vim.api.nvim_create_buf(true, false)
      bufs[#bufs + 1] = b
      vim.api.nvim_win_set_buf(0, b)
      vim.fn.jobstart({ "sh", "-c", "sleep 0.5; printf '  flowchart TD\\r\\n      A --> B\\r\\n  done\\r\\n'; sleep 5" }, { term = true })
      vim.bo[b].filetype = "sidekick_terminal"
      assert.is_true(inline.enable(b))
      assert.equals(0, #marks(b))
      wait_for(function()
        return #marks(b) == 1
      end, "diagram from terminal output")
      assert.equals(1, marks(b)[1][2])
    end)
  end)

  describe("block_at", function()
    it("covers the block's lines and fences only while expanded", function()
      local b = make_buf(concat({ "intro" }, TALL, { "after" }))
      inline.enable(b)
      wait_for(function()
        return #marks(b) == 1
      end)
      local id = inline.block_at(b, 1)
      assert.is_number(id)
      for row = 1, 6 do
        assert.equals(id, inline.block_at(b, row))
      end
      assert.is_nil(inline.block_at(b, 0))
      assert.is_nil(inline.block_at(b, 7))
    end)
  end)
end)
