describe("plugin/mermaid-viewer.lua", function()
  local commands = { "MermaidView", "MermaidClose", "MermaidToggle", "MermaidInline", "MermaidCollapse" }
  local plugs = {
    "view",
    "close",
    "toggle",
    "inline-toggle",
    "collapse-toggle",
  }

  local calls

  before_each(function()
    calls = {}
    vim.g.loaded_mermaid_viewer = nil
    package.preload["mermaid-viewer.inline"] = function()
      return {
        setup = function()
          calls.setup = (calls.setup or 0) + 1
        end,
        toggle = function(buf)
          calls.inline = buf
        end,
      }
    end
    package.preload["mermaid-viewer.collapse"] = function()
      return {
        toggle = function(buf, row)
          calls.collapse = { buf, row }
        end,
      }
    end
    package.loaded["mermaid-viewer.inline"] = nil
    package.loaded["mermaid-viewer.collapse"] = nil
    for _, name in ipairs(commands) do
      pcall(vim.api.nvim_del_user_command, name)
    end
    vim.cmd("runtime plugin/mermaid-viewer.lua")
  end)

  after_each(function()
    package.preload["mermaid-viewer.inline"] = nil
    package.preload["mermaid-viewer.collapse"] = nil
    package.loaded["mermaid-viewer.inline"] = nil
    package.loaded["mermaid-viewer.collapse"] = nil
  end)

  it("registers all commands with descriptions", function()
    local registered = vim.api.nvim_get_commands({})
    for _, name in ipairs(commands) do
      assert.is_truthy(registered[name], name)
      assert.is_truthy(registered[name].definition ~= "", name)
    end
  end)

  it("registers all <Plug> mappings", function()
    for _, name in ipairs(plugs) do
      local map = vim.fn.maparg("<Plug>(mermaid-viewer-" .. name .. ")", "n", false, true)
      assert.is_truthy(map.callback, name)
    end
  end)

  it("installs inline autocmds once at load", function()
    assert.are.equal(1, calls.setup)
  end)

  it("dispatches :MermaidInline and :MermaidCollapse with buffer and 0-based row", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a", "b", "c" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    vim.cmd("MermaidInline")
    assert.are.equal(vim.api.nvim_get_current_buf(), calls.inline)
    vim.cmd("MermaidCollapse")
    assert.are.same({ vim.api.nvim_get_current_buf(), 1 }, calls.collapse)
  end)

  it("dispatches the <Plug> mappings", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a", "b", "c" })
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    vim.fn.maparg("<Plug>(mermaid-viewer-inline-toggle)", "n", false, true).callback()
    vim.fn.maparg("<Plug>(mermaid-viewer-collapse-toggle)", "n", false, true).callback()
    assert.are.equal(vim.api.nvim_get_current_buf(), calls.inline)
    assert.are.equal(2, calls.collapse[2])
  end)
end)
