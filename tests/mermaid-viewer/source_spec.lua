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

  describe("unsupported filetype", function()
    it("returns error for non-mermaid non-markdown", function()
      local bufnr = make_buf({ "local x = 1" }, "lua")

      local result, err = source.extract(bufnr)

      assert.is_nil(result)
      assert.are.equal("Unsupported filetype", err)
    end)
  end)
end)
