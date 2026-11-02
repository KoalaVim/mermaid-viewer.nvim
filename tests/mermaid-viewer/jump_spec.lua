local mv = require("mermaid-viewer")
local collapse = require("mermaid-viewer.collapse")

describe("mermaid-viewer jump", function()
  -- rows (1-based): fences at 3, 9, 15
  local lines
  lines = {
    "# title", -- 1
    "", -- 2
    "```mermaid", -- 3
    "graph TD", -- 4
    "  A --> B", -- 5
    "```", -- 6
    "", -- 7
    "```lua", -- 8
    "print(1)", -- 9
    "```", -- 10
    "```mermaid", -- 11
    "graph LR", -- 12
    "  C --> D", -- 13
    "```", -- 14
    "", -- 15
    "```mermaid", -- 16
    "pie", -- 17
    '  "a" : 1', -- 18
    "```", -- 19
    "end", -- 20
  }
  local orig_hides = collapse.hides

  local function row()
    return vim.api.nvim_win_get_cursor(0)[1]
  end

  local function at(r)
    vim.api.nvim_win_set_cursor(0, { r, 0 })
  end

  -- the <Plug> mappings live in plugin/, which test runs don't source
  vim.g.loaded_mermaid_viewer = nil
  vim.cmd("runtime plugin/mermaid-viewer.lua")

  before_each(function()
    vim.cmd("enew!")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.bo.filetype = "markdown"
  end)

  after_each(function()
    collapse.hides = orig_hides
  end)

  it("moves to the next and previous opening fence, skipping other languages", function()
    at(1)
    assert.is_true(mv.jump(1, 1))
    assert.equals(3, row())
    mv.jump(1, 1)
    assert.equals(11, row())
    mv.jump(1, 1)
    assert.equals(16, row())
    mv.jump(-1, 1)
    assert.equals(11, row())
    mv.jump(-1, 1)
    assert.equals(3, row())
  end)

  it("goes back to the fence of the block the cursor is in, and forward past it", function()
    at(13)
    mv.jump(-1, 1)
    assert.equals(11, row())
    at(13)
    mv.jump(1, 1)
    assert.equals(16, row())
  end)

  it("takes a count and stops at the last diagram without wrapping", function()
    at(1)
    mv.jump(1, 2)
    assert.equals(11, row())
    mv.jump(1, 5)
    assert.equals(16, row())
    assert.is_false(mv.jump(1, 1))
    assert.equals(16, row())
    at(2)
    assert.is_false(mv.jump(-1, 1))
    assert.equals(2, row())
  end)

  it("uses v:count1 by default and adds to the jumplist", function()
    at(1)
    vim.cmd("clearjumps")
    vim.cmd("normal 2" .. vim.api.nvim_replace_termcodes("<Plug>(mermaid-viewer-next)", true, false, true))
    assert.equals(11, row())
    vim.cmd("normal! ``")
    assert.equals(1, row())
  end)

  it("lands on the row a collapsed block's diagram hangs from", function()
    -- the second block (rows 11-14) is collapsed: its lines are hidden
    collapse.hides = function(_, r)
      return r >= 10 and r <= 13
    end
    at(1)
    mv.jump(1, 2)
    assert.equals(10, row())
    mv.jump(1, 1)
    assert.equals(16, row())
    mv.jump(-1, 1)
    assert.equals(10, row())
  end)

  it("works as a motion", function()
    at(3)
    vim.cmd("normal d" .. vim.api.nvim_replace_termcodes("<Plug>(mermaid-viewer-next)", true, false, true))
    assert.equals("```mermaid", vim.api.nvim_buf_get_lines(0, 2, 3, false)[1])
    assert.equals("graph LR", vim.api.nvim_buf_get_lines(0, 3, 4, false)[1])
  end)

  it("jumps to the whole buffer of a mermaid buffer and does nothing elsewhere", function()
    vim.bo.filetype = "lua"
    at(5)
    assert.is_false(mv.jump(1, 1))
    assert.equals(5, row())
    vim.bo.filetype = "mermaid"
    assert.is_true(mv.jump(-1, 1))
    assert.equals(1, row())
  end)
end)
