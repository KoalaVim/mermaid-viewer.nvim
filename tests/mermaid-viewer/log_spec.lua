local config = require("mermaid-viewer.config")
local log = require("mermaid-viewer.log")

describe("log", function()
  local tmp = vim.fn.tempname()
  local orig_path = log.path

  before_each(function()
    os.remove(tmp)
    log.path = function()
      return tmp
    end
  end)

  after_each(function()
    log.path = orig_path
    config.setup({})
    os.remove(tmp)
  end)

  it("writes nothing when log is off", function()
    config.setup({})
    log.log("event", { a = 1 })
    assert.is_nil(vim.uv.fs_stat(tmp))
  end)

  it("appends a header once and one line per event with sorted fields", function()
    config.setup({ log = true })
    log.log("first", { b = 2, a = { 1, 2 } })
    log.log("second")
    local lines = vim.fn.readfile(tmp)
    local text = table.concat(lines, "\n")
    assert.matches("==== ", text)
    assert.matches("config {", text)
    assert.matches("first a={ 1, 2 } b=2", text)
    assert.matches("second$", lines[#lines])
    local _, headers = text:gsub("==== ", "")
    assert.equals(1, headers)
  end)

  it("rejects a non-boolean log option", function()
    assert.has_error(function()
      config.setup({ log = "yes" })
    end)
  end)
end)
