local size = require("mermaid-viewer.size")

local cell = { width = 10, height = 20 }

describe("mermaid-viewer.size", function()
  describe("inline", function()
    it("uses the fixed height and derives width from the aspect", function()
      -- aspect 2: 10 rows = 200px high, 400px wide = 40 cols
      local cols, rows = size.inline(2, 10, 100, cell)
      assert.equals(40, cols)
      assert.equals(10, rows)
    end)

    it("handles tall diagrams", function()
      local cols, rows = size.inline(0.3, 10, 100, cell)
      assert.equals(6, cols)
      assert.equals(10, rows)
    end)

    it("shrinks wide diagrams to the text width, preserving aspect", function()
      local cols, rows = size.inline(10, 10, 50, cell)
      assert.equals(50, cols)
      assert.equals(3, rows) -- 500x50px = 2.5 rows, rounded
    end)

    it("never goes below one row or column", function()
      local cols, rows = size.inline(100, 10, 5, cell)
      assert.equals(5, cols)
      assert.equals(1, rows)
      cols, rows = size.inline(0.001, 10, 5, cell)
      assert.equals(1, cols)
      assert.equals(10, rows)
    end)
  end)

  describe("float", function()
    it("fits a wide diagram to the float width at 1.0x", function()
      local cols, rows = size.float(4, 80, 40, 1, cell) -- float is 800x800px
      assert.equals(80, cols)
      assert.equals(10, rows)
    end)

    it("fits a tall diagram to the float height at 1.0x", function()
      local cols, rows = size.float(0.25, 80, 40, 1, cell)
      assert.equals(20, cols)
      assert.equals(40, rows)
    end)

    it("multiplies by zoom", function()
      local cols, rows = size.float(4, 80, 40, 2, cell)
      assert.equals(160, cols)
      assert.equals(20, rows)
    end)

    it("caps at 297 cells per side preserving aspect", function()
      local cols, rows = size.float(4, 80, 40, 5, cell)
      assert.equals(297, cols)
      assert.equals(37, rows)
      cols, rows = size.float(0.25, 80, 40, 20, cell)
      assert.equals(297, rows)
      assert.equals(149, cols)
    end)

    it("reports the max zoom allowed by the cap", function()
      local z = size.max_zoom(4, 80, 40, cell)
      assert.is_true(math.abs(z - 297 / 80) < 1e-9)
      local cols = size.float(4, 80, 40, z, cell)
      assert.equals(297, cols)
    end)
  end)

  describe("pixels", function()
    it("is cols * cell size when small", function()
      local w, h = size.pixels(40, 10, cell)
      assert.equals(400, w)
      assert.equals(200, h)
    end)

    it("scales down proportionally so neither side exceeds 10000", function()
      local w, h = size.pixels(297, 297, { width = 50, height = 100 }) -- 14850 x 29700
      assert.equals(10000, h)
      assert.equals(5000, w)
    end)
  end)
end)
