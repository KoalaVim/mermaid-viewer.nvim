local source = require("mermaid-viewer.source")

describe("mermaid-viewer.source", function()
  local created_buffers

  before_each(function()
    created_buffers = {}
  end)

  after_each(function()
    for _, bufnr in ipairs(created_buffers) do
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end
  end)

  local function make_buf(lines, filetype)
    local bufnr = vim.api.nvim_create_buf(false, true)
    table.insert(created_buffers, bufnr)
    if lines then
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    end
    if filetype then
      vim.bo[bufnr].filetype = filetype
    end
    return bufnr
  end

  -- markdown extraction reads the cursor of the current window, so these
  -- helpers must switch the current buffer before positioning the cursor
  local function make_current_buf(lines, filetype, cursor_line, cursor_col)
    local bufnr = make_buf(lines, filetype)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { cursor_line, cursor_col or 0 })
    return bufnr
  end

  describe("extract from .mmd buffer", function()
    it("returns full buffer content for mermaid filetype", function()
      local content = { "graph TD", "  A --> B", "  B --> C" }
      local bufnr = make_buf(content, "mermaid")

      local result, err = source.extract(bufnr)

      assert.is_nil(err)
      assert.are.equal(table.concat(content, "\n"), result)
    end)

    it("returns nil for empty buffer", function()
      local bufnr = make_buf(nil, "mermaid")

      local result, err = source.extract(bufnr)

      assert.is_nil(result)
      assert.are.equal("Buffer is empty", err)
    end)
  end)

  describe("extract from markdown", function()
    it("extracts mermaid code block at cursor", function()
      local lines = {
        "# Heading",
        "",
        "```mermaid",
        "graph TD",
        "  A --> B",
        "```",
        "",
        "Some text after.",
      }
      local bufnr = make_current_buf(lines, "markdown", 4)

      local result, err = source.extract(bufnr)

      assert.is_nil(err)
      assert.are.equal("graph TD\n  A --> B", result)
    end)

    it("returns error when cursor is outside mermaid blocks", function()
      local lines = {
        "# Heading",
        "",
        "```mermaid",
        "graph TD",
        "  A --> B",
        "```",
        "",
        "Some text after.",
      }
      local bufnr = make_current_buf(lines, "markdown", 1)

      local result, err = source.extract(bufnr)

      assert.is_nil(result)
      assert.are.equal("No mermaid diagram found at cursor", err)
    end)
  end)

  describe("blocks", function()
    it("returns every mermaid block with ranges and content", function()
      local bufnr = make_buf({
        "# H",
        "```mermaid",
        "graph TD",
        "  A --> B",
        "```",
        "```lua",
        "local x = 1",
        "```",
        "```mermaid {theme=dark}",
        "graph LR",
        "```",
      }, "markdown")

      local blocks = source.blocks(bufnr)

      assert.are.equal(2, #blocks)
      assert.are.same({ 1, 4, 2, 3, "graph TD\n  A --> B" }, {
        blocks[1].start_row,
        blocks[1].end_row,
        blocks[1].content_start,
        blocks[1].content_end,
        blocks[1].content,
      })
      assert.are.same({ 8, 10, "graph LR" }, { blocks[2].start_row, blocks[2].end_row, blocks[2].content })
    end)

    it("ignores unterminated blocks", function()
      local bufnr = make_buf({ "```mermaid", "graph TD", "  A --> B", "", "text" }, "markdown")
      assert.are.equal(0, #source.blocks(bufnr))

      bufnr = make_buf({ "```mermaid", "graph TD", "```", "```mermaid", "graph LR" }, "markdown")
      local blocks = source.blocks(bufnr)
      assert.are.equal(1, #blocks)
      assert.are.equal(0, blocks[1].start_row)
    end)

    it("returns the whole buffer of a mermaid buffer as one block drawn below it, and nothing for other filetypes", function()
      local blocks = source.blocks(make_buf({ "graph TD", "  A --> B" }, "mermaid"))
      assert.are.equal(1, #blocks)
      assert.are.equal(0, blocks[1].start_row)
      assert.are.equal(1, blocks[1].end_row)
      assert.are.equal("graph TD\n  A --> B", blocks[1].content)
      assert.is_true(blocks[1].below)
      assert.are.same({}, source.blocks(make_buf({ "" }, "mermaid")))
      assert.are.same({}, source.blocks(make_buf({ "graph TD" }, "lua")))
    end)

    it("treats a *.mmd file as a mermaid buffer whatever its filetype", function()
      local bufnr = make_buf({ "graph TD", "  A --> B" }, "text")
      vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. ".mmd")
      assert.are.equal("mermaid", source.kind(bufnr))
      assert.are.equal(1, #source.blocks(bufnr))
    end)

    it("block_at counts fence rows", function()
      local bufnr = make_buf({ "x", "```mermaid", "graph TD", "```", "y" }, "markdown")
      assert.is_nil(source.block_at(bufnr, 0))
      assert.are.equal(1, source.block_at(bufnr, 1).start_row)
      assert.are.equal(1, source.block_at(bufnr, 3).start_row)
      assert.is_nil(source.block_at(bufnr, 4))
    end)

    it("line scan fallback matches treesitter", function()
      local lines = { "a", "```mermaid", "graph TD", "```", "```mermaid x", "graph LR", "```" }
      local bufnr = make_buf(lines, "markdown")
      local expected = source.blocks(bufnr)
      local orig = vim.treesitter.get_parser
      vim.treesitter.get_parser = function()
        error("no parser")
      end
      local ok, fallback = pcall(source.blocks, bufnr)
      vim.treesitter.get_parser = orig
      assert.is_true(ok)
      assert.are.same(expected, fallback)
    end)

    it("extract_anchor returns the anchored block's source", function()
      local bufnr = make_buf({ "x", "```mermaid", "graph TD", "```" }, "markdown")
      local id = require("mermaid-viewer.blocks").scan(bufnr).added[1].id
      vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "new" })
      assert.are.equal("graph TD", source.extract_anchor(bufnr, id))
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
      local src, err = source.extract_anchor(bufnr, id)
      assert.is_nil(src)
      assert.is_truthy(err)
    end)
  end)

  describe("agent terminal output", function()
    -- what an agent UI prints for two ```mermaid blocks: fences stripped, everything indented
    local OUTPUT = {
      "  End-to-end pipeline",
      "",
      "  flowchart TD",
      "      A[\"review\"] --> B[\"Resolve config\"]",
      "      B --> C{\"Review mode\"}",
      "",
      "      C -->|default| C1[\"Workspace\"]",
      "  ctrl+o to render diagram",
      "",
      "  The graph of it all is below.",
      "  sequenceDiagram",
      "      Alice->>Bob: Hi",
      "",
      "  done",
    }

    it("finds diagrams by their declaration line and the more-indented lines after it", function()
      local bufnr = make_buf(OUTPUT, "sidekick_terminal")
      assert.are.equal("terminal", source.kind(bufnr))
      local blocks = source.blocks(bufnr)
      assert.are.equal(2, #blocks)
      assert.are.equal(2, blocks[1].start_row)
      assert.are.equal(6, blocks[1].end_row)
      assert.is_true(blocks[1].below)
      assert.are.equal(
        table.concat({
          "flowchart TD",
          '    A["review"] --> B["Resolve config"]',
          '    B --> C{"Review mode"}',
          "",
          '    C -->|default| C1["Workspace"]',
        }, "\n"),
        blocks[1].content
      )
      assert.are.equal(10, blocks[2].start_row)
      assert.are.equal(11, blocks[2].end_row)
      assert.are.equal("sequenceDiagram\n    Alice->>Bob: Hi", blocks[2].content)
    end)

    it("ignores prose and declarations without a body", function()
      local bufnr = make_buf({ "graph of nodes", "    A --> B", "flowchart TD", "next" }, "sidekick_terminal")
      assert.are.same({}, source.blocks(bufnr))
    end)

    it("finds closed ```mermaid fences at any indent", function()
      local bufnr = make_buf({ "  ```mermaid", "  graph TD", "    A --> B", "  ```", "  ```mermaid", "  graph LR" }, "sidekick_terminal")
      local blocks = source.blocks(bufnr)
      assert.are.equal(1, #blocks)
      assert.are.equal(0, blocks[1].start_row)
      assert.are.equal(3, blocks[1].end_row)
      assert.are.equal("graph TD\n  A --> B", blocks[1].content)
    end)

    it("scans only around the windows showing the terminal, following a diagram past the scanned rows", function()
      local lines = { "  flowchart TD", "      A --> B" }
      for i = 1, 2000 do
        lines[#lines + 1] = "  prose " .. i
      end
      vim.list_extend(lines, { "  sequenceDiagram", "      A->>B: hi" })
      for i = 1, 400 do
        lines[#lines + 1] = "      B->>A: " .. i
      end
      lines[#lines + 1] = "  end"
      local bufnr = make_buf(lines, "sidekick_terminal")
      -- no window: the whole buffer
      assert.are.equal(2, #source.blocks(bufnr))

      vim.api.nvim_set_current_buf(bufnr)
      -- the window starts at row 1990 (1-based): the flowchart at the top is out of range, the sequence diagram
      -- starts just below the window and is followed to its end, far past the scanned rows
      vim.api.nvim_win_set_cursor(0, { 1990, 0 })
      vim.cmd("normal! zt")
      vim.cmd("redraw")
      local blocks = source.blocks(bufnr)
      assert.are.equal(1, #blocks)
      assert.are.equal(2002, blocks[1].start_row)
      assert.are.equal(2403, blocks[1].end_row)

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      vim.cmd("normal! zt")
      vim.cmd("redraw")
      blocks = source.blocks(bufnr)
      assert.are.equal(1, #blocks)
      assert.are.equal(0, blocks[1].start_row)
    end)

    it("scans only the configured terminal filetypes", function()
      require("mermaid-viewer.config").setup({ terminal_filetypes = {} })
      local bufnr = make_buf(OUTPUT, "sidekick_terminal")
      assert.is_nil(source.kind(bufnr))
      require("mermaid-viewer.config").setup({})
    end)

    it("extracts the diagram under the cursor", function()
      make_current_buf(OUTPUT, "sidekick_terminal", 12)
      assert.are.equal("sequenceDiagram\n    Alice->>Bob: Hi", source.extract(0))
    end)
  end)

  describe("unsupported filetype", function()
    it("returns error for non-mermaid non-markdown", function()
      local bufnr = make_buf({ "local x = 1" }, "lua")

      local result, err = source.extract(bufnr)

      assert.is_nil(result)
      assert.are.equal("Unsupported filetype", err)
    end)
  end)
end)
