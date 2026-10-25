describe("mermaid-viewer.registry", function()
  local registry, kitty
  local sent
  local orig_send
  local png
  local saved_env

  before_each(function()
    for _, m in ipairs({ "config", "kitty", "terminal", "registry" }) do
      package.loaded["mermaid-viewer." .. m] = nil
    end
    saved_env = { TERM_PROGRAM = vim.env.TERM_PROGRAM, TERM = vim.env.TERM }
    vim.env.TERM_PROGRAM = "ghostty"
    vim.o.termguicolors = true
    kitty = require("mermaid-viewer.kitty")
    registry = require("mermaid-viewer.registry")
    registry._reset(1000)
    sent = {}
    orig_send = vim.api.nvim_ui_send
    vim.api.nvim_ui_send = function(data)
      sent[#sent + 1] = data
    end
    png = vim.fn.tempname() .. ".png"
    local f = assert(io.open(png, "wb"))
    f:write("fake")
    f:close()
  end)

  after_each(function()
    vim.api.nvim_ui_send = orig_send
    vim.env.TERM_PROGRAM = saved_env.TERM_PROGRAM
    os.remove(png)
  end)

  it("transmits on first acquire and reuses on the second", function()
    local a = registry.acquire("k", png, 4, 3)
    local b = registry.acquire("k", png, 4, 3)
    assert.equals(1, #sent)
    assert.equals(a.id, b.id)
    assert.equals(2, a.refcount)
    assert.equals(4, a.cols)
    assert.equals(3, a.rows)
    assert.truthy(sent[1]:find("a=p", 1, true))
  end)

  it("allocates increasing, distinct ids and a highlight with fg = id", function()
    local a = registry.acquire("a", png, 1, 1)
    local b = registry.acquire("b", png, 1, 1)
    assert.equals(1001, a.id)
    assert.equals(1002, b.id)
    assert.equals(a.id, vim.api.nvim_get_hl(0, { name = a.hl }).fg)
  end)

  it("random base is a valid 24-bit id", function()
    registry._reset()
    local img = registry.acquire("r", png, 1, 1)
    assert.is_true(img.id >= 1 and img.id <= 0xFFFFFF)
  end)

  it("deletes only when the refcount hits zero", function()
    local img = registry.acquire("k", png, 1, 1)
    registry.acquire("k", png, 1, 1)
    registry.release("k")
    assert.equals(1, #sent)
    registry.release("k")
    assert.equals(2, #sent)
    assert.truthy(sent[2]:find("a=d", 1, true))
    assert.truthy(sent[2]:find("d=I", 1, true))
    assert.truthy(sent[2]:find("i=" .. img.id, 1, true))
    assert.is_nil(registry.get("k"))
    assert.is_nil(vim.api.nvim_get_hl(0, { name = img.hl }).fg)
  end)

  it("transmits the replacement before deleting the old image", function()
    local old = registry.acquire("old", png, 2, 2)
    local new = registry.acquire("new", png, 2, 2)
    registry.release("old")
    assert.equals(3, #sent)
    assert.truthy(sent[1]:find("i=" .. old.id, 1, true) and sent[1]:find("a=t", 1, true))
    assert.truthy(sent[2]:find("i=" .. new.id, 1, true) and sent[2]:find("a=t", 1, true))
    assert.truthy(sent[3]:find("a=d", 1, true) and sent[3]:find("i=" .. old.id, 1, true))
  end)

  it("ignores release of unknown keys", function()
    registry.release("nope")
    assert.equals(0, #sent)
  end)

  it("release_all deletes every image", function()
    registry.acquire("a", png, 1, 1)
    registry.acquire("a", png, 1, 1)
    registry.acquire("b", png, 1, 1)
    registry.release_all()
    assert.equals(4, #sent)
    assert.is_nil(registry.get("a"))
  end)

  it("retransmit_all re-sends live images under their ids and skips released ones", function()
    local a = registry.acquire("a", png, 4, 3)
    local b = registry.acquire("b", png, 2, 2)
    registry.release("b")
    sent = {}
    registry.retransmit_all()
    assert.equals(1, #sent)
    assert.truthy(sent[1]:find("i=" .. a.id, 1, true))
    assert.falsy(sent[1]:find("i=" .. b.id .. ",", 1, true))
    assert.truthy(sent[1]:find("a=p", 1, true))
  end)

  it("clamps the grid to the placeholder limit", function()
    local img = registry.acquire("big", png, 500, 400)
    assert.equals(297, img.cols)
    assert.equals(297, img.rows)
  end)
end)
