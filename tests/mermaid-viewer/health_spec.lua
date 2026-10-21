describe("mermaid-viewer.health", function()
  local calls
  local orig_health, saved, orig_tgc

  local function run()
    for _, m in ipairs({ "config", "terminal", "health" }) do
      package.loaded["mermaid-viewer." .. m] = nil
    end
    calls = { ok = {}, warn = {}, error = {} }
    vim.health = {
      start = function() end,
      ok = function(msg)
        table.insert(calls.ok, msg)
      end,
      warn = function(msg)
        table.insert(calls.warn, msg)
      end,
      error = function(msg, advice)
        table.insert(calls.error, { msg = msg, advice = advice })
      end,
    }
    require("mermaid-viewer.health").check()
  end

  local function errors_matching(pat)
    local found = {}
    for _, e in ipairs(calls.error) do
      if e.msg:find(pat) then
        table.insert(found, e)
      end
    end
    return found
  end

  local function oks_matching(pat)
    local found = {}
    for _, m in ipairs(calls.ok) do
      if m:find(pat) then
        table.insert(found, m)
      end
    end
    return found
  end

  before_each(function()
    orig_health = vim.health
    orig_tgc = vim.o.termguicolors
    saved = {
      tp = vim.env.TERM_PROGRAM,
      term = vim.env.TERM,
      kitty = vim.env.KITTY_WINDOW_ID,
      ghostty = vim.env.GHOSTTY_RESOURCES_DIR,
    }
    vim.env.KITTY_WINDOW_ID = nil
    vim.env.GHOSTTY_RESOURCES_DIR = nil
    vim.o.termguicolors = true
  end)

  after_each(function()
    vim.health = orig_health
    vim.o.termguicolors = orig_tgc
    vim.env.TERM_PROGRAM = saved.tp
    vim.env.TERM = saved.term
    vim.env.KITTY_WINDOW_ID = saved.kitty
    vim.env.GHOSTTY_RESOURCES_DIR = saved.ghostty
  end)

  it("reports OK for a supported terminal and names it", function()
    vim.env.TERM_PROGRAM = "ghostty"
    run()
    assert.are.equal(1, #oks_matching("Neovim >= 0.12"))
    assert.are.equal(1, #oks_matching("termguicolors"))
    assert.are.equal(1, #oks_matching("placeholders supported.*ghostty"))
    assert.are.equal(1, #oks_matching("Configuration is valid"))
    assert.are.equal(0, #errors_matching("terminal") + #errors_matching("Terminal"))
  end)

  it("reports mmdr version or an install error", function()
    vim.env.TERM_PROGRAM = "ghostty"
    run()
    if vim.fn.executable("mmdr") == 1 then
      assert.are.equal(1, #oks_matching("^mmdr found"))
    else
      local e = errors_matching("mmdr not found")
      assert.are.equal(1, #e)
      assert.is_truthy(e[1].advice[1]:find("cargo install"))
    end
  end)

  it("reports ERROR naming supported terminals when unsupported", function()
    vim.env.TERM_PROGRAM = "WezTerm"
    run()
    local e = errors_matching("Terminal does not support")
    assert.are.equal(1, #e)
    assert.is_truthy(e[1].msg:find("WezTerm"))
    assert.is_truthy(table.concat(e[1].advice, " "):find("Kitty, Ghostty, herdr", 1, true))
  end)

  it("reports ERROR when termguicolors is off", function()
    vim.env.TERM_PROGRAM = "ghostty"
    vim.o.termguicolors = false
    run()
    assert.are.equal(1, #errors_matching("termguicolors"))
    assert.are.equal(0, #oks_matching("termguicolors"))
  end)

  it("does not mention image.nvim", function()
    run()
    for _, list in ipairs({ calls.ok, calls.warn }) do
      for _, m in ipairs(list) do
        assert.is_nil(m:find("image.nvim", 1, true))
      end
    end
    for _, e in ipairs(calls.error) do
      assert.is_nil(e.msg:find("image.nvim", 1, true))
    end
  end)
end)
