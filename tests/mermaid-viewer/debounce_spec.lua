describe("mermaid-viewer.debounce", function()
  local debounce, buf, group
  before_each(function()
    package.loaded["mermaid-viewer.debounce"] = nil
    debounce = require("mermaid-viewer.debounce")
    buf = vim.api.nvim_create_buf(false, true)
  end)
  after_each(function()
    if group then debounce.stop(group) end
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end)

  it("throttles continuous repaints without waiting for output to stop", function()
    local calls, dirty = 0, 0
    group = debounce.watch(buf, function() calls = calls + 1 end, "test", {
      throttle_ms = function() return 30 end,
      on_dirty = function() dirty = dirty + 1 end,
    })
    for _ = 1, 15 do
      vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
      vim.wait(10, function() return false end, 5)
    end
    assert.is_true(calls >= 2)
    assert.is_true(calls < 15)
    assert.equals(15, dirty)
  end)

  it("attaches line notifications when the terminal opens after the watcher was created", function()
    local calls = 0
    group = debounce.watch(buf, function() calls = calls + 1 end, "test", {
      throttle_ms = function() return 30 end,
    })
    -- Reproduce Sidekick's FileType -> watch -> TermOpen order. This hidden buffer never gets TextChanged.
    vim.api.nvim_exec_autocmds("TermOpen", { buffer = buf })
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "terminal repaint" })
    assert.is_true(vim.wait(200, function() return calls == 1 end, 5))
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "another repaint" })
    assert.is_true(vim.wait(200, function() return calls == 2 end, 5))
  end)

  it("cancels a scheduled callback when stopped", function()
    local calls = 0
    group = debounce.watch(buf, function() calls = calls + 1 end, "test", {
      throttle_ms = function() return 30 end,
    })
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
    debounce.stop(group)
    vim.wait(70, function() return false end, 5)
    assert.equals(0, calls)
  end)
end)
