local config = require("mermaid-viewer.config")
local cache = require("mermaid-viewer.cache")
local kitty = require("mermaid-viewer.kitty")
local hc = require("mermaid-viewer.headless_chrome")
local render = require("mermaid-viewer.render")

local SRC = "graph TD\n  A --> B\n  B --> C\n"

local function wait(fn)
  local result
  fn(function(...)
    result = { ... }
  end)
  vim.wait(30000, function()
    return result ~= nil
  end, 10)
  assert.is_not_nil(result, "timed out")
  return unpack(result)
end

local function arg(cmd, flag)
  for i, a in ipairs(cmd) do
    if a == flag then
      return cmd[i + 1]
    end
  end
end

describe("mermaid-viewer.headless_chrome", function()
  local fake_js

  before_each(function()
    fake_js = vim.fn.tempname() .. ".js"
    vim.fn.writefile({ "" }, fake_js)
    vim.g.mkdp_preview_options = nil
  end)

  after_each(function()
    os.remove(fake_js)
    vim.g.mkdp_preview_options = nil
    config.setup({})
  end)

  it("rejects unknown renderers", function()
    assert.has_error(function()
      config.setup({ renderer = "nope" })
    end)
  end)

  it("builds a node command with mermaid.js, theme and size", function()
    config.setup({
      renderer = "headless-chrome",
      theme = "dark",
      headless_chrome = { mermaid_js = fake_js, node_path = "mynode", puppeteer = "/pp", background = "#000" },
    })
    local cmd = assert(hc.cmd("in.mmd", "out.png", 400, 300))
    assert.equals("mynode", cmd[1])
    assert.equals(hc.script(), cmd[2])
    assert.equals(1, vim.fn.filereadable(cmd[2]))
    assert.equals(fake_js, arg(cmd, "--mermaid"))
    assert.equals(1, #vim.tbl_filter(function(a)
      return a == "--mermaid"
    end, cmd))
    assert.equals("/pp", arg(cmd, "--puppeteer"))
    assert.equals("dark", arg(cmd, "--theme"))
    assert.equals("400", arg(cmd, "--width"))
    assert.equals("300", arg(cmd, "--height"))
    assert.equals("#000", arg(cmd, "--background"))
    assert.equals("true", arg(cmd, "--classic-colors"))
    assert.is_nil(arg(cmd, "--config"))
  end)

  it("can turn the classic colors off", function()
    config.setup({ renderer = "headless-chrome", headless_chrome = { mermaid_js = fake_js, classic_colors = false } })
    local cmd = assert(hc.cmd("in.mmd", "out.png"))
    assert.is_nil(arg(cmd, "--classic-colors"))
  end)

  it("passes g:mkdp_preview_options.maid as mermaid config", function()
    config.setup({ renderer = "headless-chrome", headless_chrome = { mermaid_js = fake_js } })
    vim.g.mkdp_preview_options = { maid = { flowchart = { curve = "basis" } } }
    local cmd = assert(hc.cmd("in.mmd", "out.png"))
    assert.same({ flowchart = { curve = "basis" } }, vim.json.decode(arg(cmd, "--config")))
    assert.is_nil(arg(cmd, "--width"))
  end)

  it("errors when mermaid.js is missing", function()
    config.setup({ renderer = "headless-chrome", headless_chrome = { mermaid_js = "/does/not/exist.js" } })
    local cmd, err = hc.cmd("in.mmd", "out.png")
    assert.is_nil(cmd)
    assert.matches("not found", err)
    local rerr = wait(function(cb)
      render.cached(SRC, {}, cb)
    end)
    assert.matches("not found", rerr)
  end)

  it("keeps renders of different renderers apart", function()
    config.setup({ renderer = "mmdr" })
    local a = cache.hash(SRC)
    config.setup({ renderer = "headless-chrome" })
    assert.are_not.equal(a, cache.hash(SRC))
  end)

  it("passes a list of mermaid.js files in order", function()
    local fake2 = vim.fn.tempname() .. ".js"
    vim.fn.writefile({ "" }, fake2)
    config.setup({ renderer = "headless-chrome", headless_chrome = { mermaid_js = { fake_js, fake2 } } })
    local cmd = assert(hc.cmd("in.mmd", "out.png"))
    local got = {}
    for i, a in ipairs(cmd) do
      if a == "--mermaid" then
        table.insert(got, cmd[i + 1])
      end
    end
    assert.same({ fake_js, fake2 }, got)
    os.remove(fake2)
  end)

  ;(vim.fn.executable("mmdc") == 1 and it or pending)("defaults to mermaid-cli's mermaid only", function()
    config.setup({ renderer = "headless-chrome" })
    local js = assert(hc.mermaid_js())
    assert.equals(1, #js)
    assert.matches("node_modules/mermaid/dist/mermaid%.min%.js$", js[1])
  end)

  -- end-to-end, only when mermaid-cli's mermaid.js, node and puppeteer are all available
  local e2e = hc.mermaid_js() and vim.fn.executable("node") == 1 and hc.puppeteer_dir()
  ;(e2e and it or pending)("renders through headless Chrome at natural and target size", function()
    config.setup({ renderer = "headless-chrome" })
    cache.clear()
    local real_cell = kitty.cell_size
    kitty.cell_size = function()
      return { width = 10, height = 20 }
    end
    local err, res = wait(function(cb)
      render.diagram(SRC, function(aspect)
        return math.floor(aspect * 20 * 2), 20
      end, cb)
    end)
    kitty.cell_size = real_cell
    assert.is_nil(err)
    assert.is_true(res.aspect > 0)
    -- scaled to fit the target grid, touching it on one side
    local tw, th = res.cols * 10, res.rows * 20
    assert.is_true(res.width_px <= tw + 2 and res.height_px <= th + 2)
    assert.is_true(math.abs(res.width_px - tw) <= 2 or math.abs(res.height_px - th) <= 2)
    assert.is_true(res.height_px > 300, tostring(res.height_px))

    local perr = wait(function(cb)
      render.cached("graph TD; A-->", {}, cb)
    end)
    assert.matches("Parse error", perr)

    -- entity aliases fail in old mermaid (e.g. 10.2.3); mermaid-cli's current mermaid renders them
    if vim.fn.executable("mmdc") == 1 then
      local aerr = wait(function(cb)
        render.cached('erDiagram\n  T["tasks (NEW)"] {\n    string id PK\n  }\n  U ||--o{ T : has\n', {}, cb)
      end)
      assert.is_nil(aerr)
    end
    cache.clear()
  end)
end)
