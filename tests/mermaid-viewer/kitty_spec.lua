describe("mermaid-viewer.kitty placeholders", function()
  local kitty
  local sent
  local orig_send
  local png

  before_each(function()
    package.loaded["mermaid-viewer.config"] = nil
    package.loaded["mermaid-viewer.kitty"] = nil
    package.loaded["mermaid-viewer.terminal"] = nil
    kitty = require("mermaid-viewer.kitty")
    sent = {}
    orig_send = vim.api.nvim_ui_send
    vim.api.nvim_ui_send = function(data)
      sent[#sent + 1] = data
    end
    png = vim.fn.tempname() .. ".png"
    local f = assert(io.open(png, "wb"))
    f:write("\137PNG fake")
    f:close()
  end)

  after_each(function()
    vim.api.nvim_ui_send = orig_send
    os.remove(png)
  end)

  local P = vim.fn.nr2char(0x10EEEE)
  local function d(n)
    return vim.fn.nr2char(tonumber(({ "0305", "030D", "030E" })[n], 16))
  end

  it("builds a 3x2 placeholder grid", function()
    local lines = kitty.placeholder_lines(3, 2)
    assert.same({
      P .. d(1) .. d(1) .. P .. d(1) .. d(2) .. P .. d(1) .. d(3),
      P .. d(2) .. d(1) .. P .. d(2) .. d(2) .. P .. d(2) .. d(3),
    }, lines)
  end)

  it("supports sub-ranges that keep absolute cell coordinates", function()
    local lines = kitty.placeholder_lines(3, 2, { row_start = 2, col_start = 2, col_end = 3 })
    assert.same({ P .. d(2) .. d(2) .. P .. d(2) .. d(3) }, lines)
  end)

  it("caps the grid at the diacritics table size", function()
    assert.equals(297, kitty.max_cells)
    assert.equals(297, #kitty.placeholder_lines(1, 400))
  end)

  it("produces virt_lines chunks with the highlight", function()
    local virt = kitty.placeholder_virt_lines(3, 2, "Hl")
    assert.equals(2, #virt)
    assert.same({ { kitty.placeholder_lines(3, 2)[1], "Hl" } }, virt[1])
  end)

  it("sets a highlight whose fg is the image id", function()
    local id = 0x123456
    local name = kitty.set_highlight(id)
    local hl = vim.api.nvim_get_hl(0, { name = name })
    assert.equals(id, hl.fg)
    assert.is_true(hl.nocombine)
    kitty.clear_highlight(id)
  end)

  it("transmits and creates the virtual placement in a single send", function()
    assert.is_true(kitty.transmit_virtual(png, 77, 3, 2))
    assert.equals(1, #sent)
    assert.truthy(sent[1]:find("a=t", 1, true))
    local placement = sent[1]:match("\27_G[^\27]*a=p[^\27]*\27\\")
    assert.truthy(placement)
    for _, kv in ipairs({ "U=1", "i=77", "c=3", "r=2", "q=2" }) do
      assert.truthy(placement:find(kv, 1, true), kv)
    end
  end)

  it("returns false for an unreadable png without sending", function()
    assert.is_false(kitty.transmit_virtual("/nonexistent.png", 1, 1, 1))
    assert.equals(0, #sent)
  end)

  it("deletes with d=I", function()
    kitty.delete_image(9)
    assert.equals(1, #sent)
    assert.truthy(sent[1]:find("a=d", 1, true))
    assert.truthy(sent[1]:find("d=I", 1, true))
    assert.truthy(sent[1]:find("i=9", 1, true))
  end)

  it("omits q=2 in debug mode", function()
    require("mermaid-viewer.config").setup({ debug = true })
    kitty.transmit_virtual(png, 5, 1, 1)
    kitty.delete_image(5)
    for _, s in ipairs(sent) do
      assert.is_nil(s:find("q=2", 1, true))
    end
  end)
end)
