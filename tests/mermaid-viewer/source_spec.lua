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

    it("returns nothing for non-markdown buffers", function()
      assert.are.same({}, source.blocks(make_buf({ "graph TD" }, "mermaid")))
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

  describe("unsupported filetype", function()
    it("returns error for non-mermaid non-markdown", function()
      local bufnr = make_buf({ "local x = 1" }, "lua")

      local result, err = source.extract(bufnr)

      assert.is_nil(result)
      assert.are.equal("Unsupported filetype", err)
    end)
  end)
end)
