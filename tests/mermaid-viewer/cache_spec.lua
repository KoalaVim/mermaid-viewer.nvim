local config = require("mermaid-viewer.config")
local cache = require("mermaid-viewer.cache")
local render = require("mermaid-viewer.render")
local temp = require("mermaid-viewer.temp")

local SRC = "graph TD\n  A --> B\n"

--- Wait for a callback-style call
local function wait(fn)
  local result
  fn(function(...)
    result = { ... }
  end)
  vim.wait(10000, function()
    return result ~= nil
  end, 10)
  assert.is_not_nil(result, "timed out")
  return unpack(result)
end

describe("mermaid-viewer.cache", function()
  local real_system, runs

  before_each(function()
    cache.clear()
    config.setup({})
    runs = 0
    real_system = vim.system
    vim.system = function(cmd, opts, on_exit)
      runs = runs + 1
      return real_system(cmd, opts, on_exit)
    end
  end)

  after_each(function()
    vim.system = real_system
    cache.clear()
  end)

  it("does not invoke mmdr for an identical second render", function()
    local err, path = wait(function(cb)
      render.cached(SRC, { width = 400, height = 300 }, cb)
    end)
    assert.is_nil(err)
    assert.equals(1, runs)
    local err2, path2 = wait(function(cb)
      render.cached(SRC, { width = 400, height = 300 }, cb)
    end)
    assert.is_nil(err2)
    assert.equals(path, path2)
    assert.equals(1, runs)
  end)

  it("re-renders for a different size or theme", function()
    wait(function(cb)
      render.cached(SRC, { width = 400, height = 300 }, cb)
    end)
    wait(function(cb)
      render.cached(SRC, { width = 500, height = 300 }, cb)
    end)
    config.setup({ theme = "dark" })
    wait(function(cb)
      render.cached(SRC, { width = 400, height = 300 }, cb)
    end)
    assert.equals(3, runs)
  end)

  it("coalesces concurrent identical requests", function()
    local done = 0
    for _ = 1, 3 do
      render.cached(SRC, { width = 400, height = 300 }, function(err)
        assert.is_nil(err)
        done = done + 1
      end)
    end
    vim.wait(10000, function()
      return done == 3
    end, 10)
    assert.equals(3, done)
    assert.equals(1, runs)
  end)

  it("deletes the temp input after each render", function()
    wait(function(cb)
      render.cached(SRC, { width = 400, height = 300 }, cb)
    end)
    assert.same({}, vim.fn.glob(temp.dir() .. "/*.mmd", false, true))
    assert.equals(1, #vim.fn.glob(temp.dir() .. "/*.png", false, true))
  end)

  it("does not cache failures", function()
    local err = wait(function(cb)
      render.cached("this is not mermaid at all ((((", { width = 400, height = 300 }, cb)
    end)
    assert.is_string(err)
    assert.same({}, vim.fn.glob(temp.dir() .. "/*", false, true))
  end)

  it("removes the whole dir on cleanup_all", function()
    wait(function(cb)
      render.cached(SRC, { width = 400, height = 300 }, cb)
    end)
    local dir = temp.dir()
    assert.equals(1, vim.fn.isdirectory(dir))
    temp.cleanup_all()
    assert.equals(0, vim.fn.isdirectory(dir))
  end)

  it("registers a VimLeavePre cleanup", function()
    temp.dir()
    local autocmds = vim.api.nvim_get_autocmds({ group = "mermaid_viewer_temp_cleanup", event = "VimLeavePre" })
    assert.equals(1, #autocmds)
  end)
end)
