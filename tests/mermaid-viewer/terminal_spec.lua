describe("mermaid-viewer.terminal", function()
  local terminal, registry
  local sent, notified
  local orig_send, orig_notify
  local png
  local saved

  local function reload()
    for _, m in ipairs({ "config", "kitty", "terminal", "registry" }) do
      package.loaded["mermaid-viewer." .. m] = nil
    end
    terminal = require("mermaid-viewer.terminal")
    registry = require("mermaid-viewer.registry")
    registry._reset(1)
  end

  local function env(program, term)
    vim.env.TERM_PROGRAM = program
    vim.env.TERM = term
    vim.env.KITTY_WINDOW_ID = nil
    vim.env.GHOSTTY_RESOURCES_DIR = nil
  end

  before_each(function()
    saved = {
      TERM_PROGRAM = vim.env.TERM_PROGRAM,
      TERM = vim.env.TERM,
      KITTY_WINDOW_ID = vim.env.KITTY_WINDOW_ID,
      GHOSTTY_RESOURCES_DIR = vim.env.GHOSTTY_RESOURCES_DIR,
      tgc = vim.o.termguicolors,
    }
    vim.o.termguicolors = true
    reload()
    sent, notified = {}, {}
    orig_send, orig_notify = vim.api.nvim_ui_send, vim.notify
    vim.api.nvim_ui_send = function(data)
      sent[#sent + 1] = data
    end
    vim.notify = function(msg, level)
      notified[#notified + 1] = { msg = msg, level = level }
    end
    png = vim.fn.tempname() .. ".png"
    local f = assert(io.open(png, "wb"))
    f:write("fake")
    f:close()
  end)

  after_each(function()
    vim.api.nvim_ui_send, vim.notify = orig_send, orig_notify
    for k, v in pairs(saved) do
      if k ~= "tgc" then
        vim.env[k] = v
      end
    end
    vim.o.termguicolors = saved.tgc
    terminal._reset()
    os.remove(png)
  end)

  describe("detection", function()
    it("accepts kitty, ghostty and herdr via TERM_PROGRAM", function()
      for _, p in ipairs({ "ghostty", "kitty", "herdr" }) do
        env(p, "xterm-256color")
        assert.is_true((terminal.supported()), p)
      end
    end)

    it("accepts kitty/ghostty via TERM and env markers when TERM_PROGRAM is unset", function()
      env(nil, "xterm-kitty")
      assert.is_true((terminal.supported()))
      env(nil, "xterm-ghostty")
      assert.is_true((terminal.supported()))
      env(nil, "xterm-256color")
      vim.env.KITTY_WINDOW_ID = "1"
      assert.is_true((terminal.supported()))
    end)

    it("rejects WezTerm and tmux even with leftover markers", function()
      env("WezTerm", "xterm-256color")
      vim.env.KITTY_WINDOW_ID = "1"
      local ok, reason = terminal.supported()
      assert.is_false(ok)
      assert.truthy(reason:find("WezTerm", 1, true))
      env("tmux", "tmux-256color")
      assert.is_false((terminal.supported()))
    end)

    it("requires termguicolors", function()
      env("ghostty", "xterm-256color")
      vim.o.termguicolors = false
      local ok, reason = terminal.supported()
      assert.is_false(ok)
      assert.truthy(reason:find("termguicolors", 1, true))
    end)

    it("config override wins in both directions", function()
      env("WezTerm", "xterm-256color")
      require("mermaid-viewer.config").setup({ terminal = { placeholders = true } })
      assert.is_true((terminal.supported()))
      env("ghostty", "xterm-ghostty")
      require("mermaid-viewer.config").setup({ terminal = { placeholders = false } })
      assert.is_false((terminal.supported()))
    end)
  end)

  describe("gating", function()
    it("sends nothing and warns exactly once on WezTerm", function()
      env("WezTerm", "xterm-256color")
      assert.is_nil((registry.acquire("a", png, 2, 2)))
      assert.is_nil((registry.acquire("b", png, 2, 2)))
      registry.release("a")
      assert.equals(0, #sent)
      assert.equals(1, #notified)
      assert.equals(vim.log.levels.WARN, notified[1].level)
      assert.truthy(notified[1].msg:find("Ghostty", 1, true))
    end)

    it("sends and does not warn on a supported terminal", function()
      env("ghostty", "xterm-256color")
      assert.is_not_nil(registry.acquire("a", png, 2, 2))
      assert.equals(1, #sent)
      assert.equals(0, #notified)
    end)
  end)

  describe("debug", function()
    it("logs kitty replies from TermResponse and sends without q=2", function()
      env("ghostty", "xterm-256color")
      require("mermaid-viewer.config").setup({ debug = true })
      registry.acquire("a", png, 2, 2)
      assert.equals(1, #sent)
      assert.is_nil(sent[1]:find("q=2", 1, true))

      vim.api.nvim_exec_autocmds("TermResponse", { data = { sequence = "\27_Gi=1;OK" } })
      vim.api.nvim_exec_autocmds("TermResponse", { data = { sequence = "\27[?62c" } })
      assert.same({ "i=1;OK" }, terminal.responses)
      assert.equals(1, #notified)
      assert.truthy(notified[1].msg:find("i=1;OK", 1, true))
      assert.equals(vim.log.levels.DEBUG, notified[1].level)
    end)

    it("does not log when debug is off", function()
      env("ghostty", "xterm-256color")
      registry.acquire("a", png, 2, 2)
      assert.truthy(sent[1]:find("q=2", 1, true))
      vim.api.nvim_exec_autocmds("TermResponse", { data = { sequence = "\27_Gi=1;OK" } })
      assert.same({}, terminal.responses)
    end)
  end)
end)
