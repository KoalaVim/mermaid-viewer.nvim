local blocks = require("mermaid-viewer.blocks")
local config = require("mermaid-viewer.config")

describe("mermaid-viewer.blocks", function()
  local bufs

  before_each(function()
    bufs = {}
  end)

  after_each(function()
    for _, b in ipairs(bufs) do
      pcall(blocks.detach, b)
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
  end)

  local function make_buf(lines)
    local b = vim.api.nvim_create_buf(false, true)
    table.insert(bufs, b)
    vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
    vim.bo[b].filetype = "markdown"
    return b
  end

  local two = {
    "# T",
    "```mermaid",
    "graph TD",
    "  A --> B",
    "```",
    "text",
    "```mermaid",
    "graph LR",
    "  X --> Y",
    "```",
  }

  it("reports all blocks as added on first scan, then unchanged", function()
    local b = make_buf(two)
    local d = blocks.scan(b)
    assert.are.equal(2, #d.added)
    assert.are.equal(0, #d.removed + #d.changed + #d.unchanged)
    assert.are_not.equal(d.added[1].id, d.added[2].id)
    local d2 = blocks.scan(b)
    assert.are.equal(2, #d2.unchanged)
    assert.are.equal(0, #d2.added + #d2.removed + #d2.changed)
  end)

  it("keeps the anchor id when lines are inserted above", function()
    local b = make_buf(two)
    local id = blocks.scan(b).added[1].id
    vim.api.nvim_buf_set_lines(b, 0, 0, false, { "a", "b", "c" })
    local d = blocks.scan(b)
    assert.are.equal(2, #d.unchanged)
    assert.are.equal(id, d.unchanged[1].id)
    assert.are.equal(4, d.unchanged[1].start_row)
    assert.are.equal(7, d.unchanged[1].end_row)
    assert.are.equal(id, blocks.get(b, id).id)
    assert.are.equal(4, blocks.get(b, id).start_row)
  end)

  it("reports only the edited block as changed", function()
    local b = make_buf(two)
    local d0 = blocks.scan(b)
    vim.api.nvim_buf_set_lines(b, 3, 4, false, { "  A --> C" })
    local d = blocks.scan(b)
    assert.are.equal(1, #d.changed)
    assert.are.equal(1, #d.unchanged)
    assert.are.equal(d0.added[1].id, d.changed[1].id)
    assert.are.equal("graph TD\n  A --> C", d.changed[1].content)
    assert.are.equal(d0.added[2].id, d.unchanged[1].id)
  end)

  it("reports a deleted block as removed", function()
    local b = make_buf(two)
    local d0 = blocks.scan(b)
    vim.api.nvim_buf_set_lines(b, 1, 5, false, {})
    local d = blocks.scan(b)
    assert.are.equal(1, #d.removed)
    assert.are.equal(d0.added[1].id, d.removed[1].id)
    assert.are.equal(1, #d.unchanged)
    assert.are.equal(d0.added[2].id, d.unchanged[1].id)
    assert.is_nil(blocks.get(b, d0.added[1].id))
  end)

  it("deleting a block directly above an adjacent one removes the right anchor", function()
    local b = make_buf({ "```mermaid", "graph TD", "  A --> B", "```", "```mermaid", "graph LR", "  X --> Y", "```" })
    local d0 = blocks.scan(b)
    vim.api.nvim_buf_set_lines(b, 0, 4, false, {})
    local d = blocks.scan(b)
    assert.are.equal(1, #d.removed)
    assert.are.equal(d0.added[1].id, d.removed[1].id)
    assert.are.equal(d0.added[2].id, d.unchanged[1].id)
  end)

  it("reports a new block as added", function()
    local b = make_buf(two)
    blocks.scan(b)
    vim.api.nvim_buf_set_lines(b, 5, 5, false, { "```mermaid", "graph TD", "  Q --> R", "```" })
    local d = blocks.scan(b)
    assert.are.equal(1, #d.added)
    assert.are.equal(2, #d.unchanged)
    assert.are.equal(5, d.added[1].start_row)
  end)

  it("at_row finds the block including fences", function()
    local b = make_buf(two)
    local d = blocks.scan(b)
    assert.are.equal(d.added[1].id, blocks.at_row(b, 1).id)
    assert.are.equal(d.added[2].id, blocks.at_row(b, 9).id)
    assert.is_nil(blocks.at_row(b, 5))
  end)

  describe("attach", function()
    local saved

    before_each(function()
      saved = config.options.debounce_ms
      config.options.debounce_ms = 20
    end)

    after_each(function()
      config.options.debounce_ms = saved
    end)

    it("calls on_diff for the initial blocks and after debounced edits only when something changed", function()
      local b = make_buf(two)
      vim.api.nvim_set_current_buf(b)
      local calls = {}
      blocks.attach(b, function(diff)
        table.insert(calls, diff)
      end)
      assert.are.equal(1, #calls)
      assert.are.equal(2, #calls[1].added)

      -- edit outside any block: rescan runs but nothing is reported
      vim.api.nvim_buf_set_lines(b, 5, 6, false, { "other text" })
      vim.api.nvim_exec_autocmds("TextChanged", { buffer = b })
      vim.wait(150)
      assert.are.equal(1, #calls)

      vim.api.nvim_buf_set_lines(b, 3, 4, false, { "  A --> Z" })
      vim.api.nvim_exec_autocmds("TextChanged", { buffer = b })
      assert.is_true(vim.wait(1000, function()
        return #calls == 2
      end))
      assert.are.equal(1, #calls[2].changed)
      assert.are.equal(1, #calls[2].unchanged)
    end)

    it("stops reporting after detach", function()
      local b = make_buf(two)
      vim.api.nvim_set_current_buf(b)
      local n = 0
      blocks.attach(b, function()
        n = n + 1
      end)
      blocks.detach(b)
      vim.api.nvim_buf_set_lines(b, 3, 4, false, { "  A --> Z" })
      vim.api.nvim_exec_autocmds("TextChanged", { buffer = b })
      vim.wait(150)
      assert.are.equal(1, n)
    end)
  end)
end)
