local config = require("mermaid-viewer.config")
local cache = require("mermaid-viewer.cache")
local kitty = require("mermaid-viewer.kitty")
local render = require("mermaid-viewer.render")

local SRC = "graph TD\n  A --> B\n  B --> C\n"

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

describe("mermaid-viewer.render", function()
  local real_system, real_cell, cmds

  before_each(function()
    cache.clear()
    config.setup({})
    cmds = {}
    real_system = vim.system
    real_cell = kitty.cell_size
    kitty.cell_size = function()
      return { width = 10, height = 20 }
    end
    vim.system = function(cmd, opts, on_exit)
      cmds[#cmds + 1] = cmd
      return real_system(cmd, opts, on_exit)
    end
  end)

  after_each(function()
    vim.system = real_system
    kitty.cell_size = real_cell
    cache.clear()
  end)

  local function has_theme(cmd, theme)
    for i, a in ipairs(cmd) do
      if a == "--theme" and cmd[i + 1] == theme then
        return true
      end
    end
    return false
  end

  it("passes the configured theme in every render path", function()
    config.setup({ theme = "dark" })
    wait(function(cb)
      render.render(SRC, { width = 400, height = 300 }, cb)
    end)
    wait(function(cb)
      render.cached(SRC, { width = 400, height = 300 }, cb)
    end)
    wait(function(cb)
      render.diagram(SRC, { cols = 30, rows = 10 }, cb)
    end)
    assert.is_true(#cmds >= 3)
    for _, cmd in ipairs(cmds) do
      assert.is_true(has_theme(cmd, "dark"), table.concat(cmd, " "))
    end
  end)

  it("keeps the legacy render signature", function()
    local err, path, input = wait(function(cb)
      render.render(SRC, { width = 400, height = 300 }, cb)
    end)
    assert.is_nil(err)
    assert.equals(1, vim.fn.filereadable(path))
    os.remove(path)
    os.remove(input)
  end)

  it("learns the aspect with a natural render, then renders at the target size", function()
    local err, res = wait(function(cb)
      render.diagram(SRC, function(aspect)
        return math.floor(aspect * 20 * 2), 20 -- far bigger than natural
      end, cb)
    end)
    assert.is_nil(err)
    assert.equals(2, #cmds)
    assert.is_false(vim.tbl_contains(cmds[1], "--width"))
    assert.is_true(vim.tbl_contains(cmds[2], "--width"))
    assert.is_true(res.aspect > 0)
    assert.equals(cache.get_aspect(cache.hash(SRC)), res.aspect)
    assert.is_true(math.abs(res.height_px - 400) <= 2)
  end)

  it("reuses the natural render when within 10% of the target", function()
    local _, first = wait(function(cb)
      render.diagram(SRC, { cols = 1, rows = 1 }, cb)
    end)
    cmds = {}
    local nw, nh = first.width_px, first.height_px
    -- a grid that maps to (almost) the natural pixel size
    local _, res = wait(function(cb)
      render.diagram(SRC, { cols = math.floor(nw / 10 + 0.5), rows = math.floor(nh / 20 + 0.5) }, cb)
    end)
    assert.equals(0, #cmds)
    assert.equals(nw, res.width_px)
  end)

  it("reports mmdr errors", function()
    local err, res = wait(function(cb)
      render.diagram("not mermaid ((((", { cols = 10, rows = 5 }, cb)
    end)
    assert.is_string(err)
    assert.is_nil(res)
  end)
end)
