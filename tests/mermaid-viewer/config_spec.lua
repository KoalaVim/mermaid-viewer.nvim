describe("mermaid-viewer.config", function()
  local config

  before_each(function()
    package.loaded["mermaid-viewer.config"] = nil
    config = require("mermaid-viewer.config")
  end)

  it("has sensible defaults", function()
    assert.equals("mmdr", config.options.mmdr_path)
    assert.equals("default", config.options.theme)
    assert.equals(300, config.options.debounce_ms)
    assert.equals(false, config.options.fast_text)
    assert.equals(0.8, config.options.float.width)
    assert.equals(0.8, config.options.float.height)
    assert.equals("rounded", config.options.float.border)
    assert.same({}, config.options.float.win_config)
    assert.equals(true, config.options.auto_update)
    assert.equals(1.5, config.options.zoom_step)
    assert.equals(5.0, config.options.max_zoom)
    assert.is_nil(config.options.pan_step)
  end)

  it("has debug off and terminal detection on auto by default", function()
    assert.equals(false, config.options.debug)
    assert.is_nil(config.options.terminal.placeholders)
  end)

  it("accepts debug and terminal overrides", function()
    config.setup({ debug = true, terminal = { placeholders = false } })
    assert.equals(true, config.options.debug)
    assert.equals(false, config.options.terminal.placeholders)
  end)

  it("rejects invalid debug/terminal values", function()
    assert.has_error(function()
      config.setup({ debug = "yes" })
    end)
    assert.has_error(function()
      config.setup({ terminal = { placeholders = "yes" } })
    end)
  end)

  it("has sensible default keymaps", function()
    assert.equals("i", config.options.keys.zoom_in)
    assert.equals("o", config.options.keys.zoom_out)
    assert.equals("0", config.options.keys.zoom_reset)
    assert.is_nil(config.options.keys.pan_up)
    assert.same({ "q", "<Esc>" }, config.options.keys.close)
  end)

  it("merges partial overrides", function()
    config.setup({ theme = "dark", debounce_ms = 500 })
    assert.equals("dark", config.options.theme)
    assert.equals(500, config.options.debounce_ms)
    assert.equals("mmdr", config.options.mmdr_path) -- unchanged
  end)

  it("deep merges nested tables", function()
    config.setup({ float = { width = 0.6 } })
    assert.equals(0.6, config.options.float.width)
    assert.equals(0.8, config.options.float.height) -- unchanged
    assert.equals("rounded", config.options.float.border) -- unchanged
  end)

  it("deep merges nested keys table", function()
    config.setup({ keys = { zoom_in = "=" } })
    assert.equals("=", config.options.keys.zoom_in)
    assert.equals("o", config.options.keys.zoom_out) -- unchanged
    assert.same({ "q", "<Esc>" }, config.options.keys.close) -- unchanged
  end)

  it("works with no arguments", function()
    config.setup()
    assert.equals("mmdr", config.options.mmdr_path)
    assert.equals("default", config.options.theme)
  end)

  it("works with an empty table", function()
    config.setup({})
    assert.equals("mmdr", config.options.mmdr_path)
  end)

  it("does not mutate defaults across repeated setups", function()
    config.setup({ theme = "dark" })
    assert.equals("dark", config.options.theme)

    config.setup({ debounce_ms = 100 })
    assert.equals("default", config.options.theme) -- back to default, not "dark"
    assert.equals(100, config.options.debounce_ms)
  end)

  it("overrides every top-level default when given a full config", function()
    config.setup({
      mmdr_path = "/usr/local/bin/mmdr",
      theme = "dark",
      debounce_ms = 42,
      fast_text = true,
      float = { width = 0.5, height = 0.5, border = "single" },
      keys = {
        zoom_in = "=",
        zoom_out = "_",
        zoom_reset = "r",
        close = { "<C-c>" },
      },
      auto_update = false,
      zoom_step = 2,
      max_zoom = 10,
    })

    assert.equals("/usr/local/bin/mmdr", config.options.mmdr_path)
    assert.equals("dark", config.options.theme)
    assert.equals(42, config.options.debounce_ms)
    assert.equals(true, config.options.fast_text)
    assert.same({ width = 0.5, height = 0.5, border = "single", win_config = {} }, config.options.float)
    assert.equals(false, config.options.auto_update)
    assert.equals(2, config.options.zoom_step)
    assert.equals(10, config.options.max_zoom)
  end)

  describe("removed pan options", function()
    local real_notify, notes

    before_each(function()
      real_notify = vim.notify
      notes = {}
      vim.notify = function(msg, level)
        notes[#notes + 1] = { msg = msg, level = level }
      end
    end)

    after_each(function()
      vim.notify = real_notify
    end)

    it("warns once naming native motions, ignores the options and keeps the rest", function()
      config.setup({ pan_step = 3, keys = { pan_up = "K", pan_left = "H", zoom_in = "=" } })
      config.setup({ pan_step = 3, keys = { pan_down = "J" } })
      assert.equals(1, #notes)
      assert.equals(vim.log.levels.WARN, notes[1].level)
      assert.truthy(notes[1].msg:find("pan_step", 1, true))
      assert.truthy(notes[1].msg:find("keys.pan_up", 1, true))
      assert.truthy(notes[1].msg:find("native motions", 1, true))
      assert.is_nil(config.options.pan_step)
      assert.is_nil(config.options.keys.pan_up)
      assert.is_nil(config.options.keys.pan_down)
    end)

    it("does not warn without removed options and does not mutate the passed table", function()
      config.setup({ keys = { zoom_in = "=" } })
      assert.equals(0, #notes)
      local opts = { pan_step = 2, keys = { pan_right = "L" } }
      config.setup(opts)
      assert.equals(2, opts.pan_step)
      assert.equals("L", opts.keys.pan_right)
    end)
  end)

  describe("validation", function()
    it("validates config types", function()
      assert.has_error(function()
        config.setup({ mmdr_path = 123 })
      end)
    end)

    it("rejects a non-string theme", function()
      assert.has_error(function()
        config.setup({ theme = 42 })
      end)
    end)

    it("rejects a non-number debounce_ms", function()
      assert.has_error(function()
        config.setup({ debounce_ms = "300" })
      end)
    end)

    it("rejects a non-boolean fast_text", function()
      assert.has_error(function()
        config.setup({ fast_text = "false" })
      end)
    end)

    it("rejects a non-table float", function()
      assert.has_error(function()
        config.setup({ float = "big" })
      end)
    end)

    it("rejects a non-table float.win_config", function()
      assert.has_error(function()
        config.setup({ float = { win_config = "big" } })
      end)
    end)

    it("rejects a non-table keys", function()
      assert.has_error(function()
        config.setup({ keys = "none" })
      end)
    end)

    it("rejects a non-boolean auto_update", function()
      assert.has_error(function()
        config.setup({ auto_update = 1 })
      end)
    end)

    it("rejects a non-number zoom_step", function()
      assert.has_error(function()
        config.setup({ zoom_step = "1.5" })
      end)
    end)

    it("rejects a non-number max_zoom", function()
      assert.has_error(function()
        config.setup({ max_zoom = "5" })
      end)
    end)

    it("does not error on a fully valid config", function()
      assert.has_no.errors(function()
        config.setup({ theme = "dark", debounce_ms = 100 })
      end)
    end)
  end)
end)
