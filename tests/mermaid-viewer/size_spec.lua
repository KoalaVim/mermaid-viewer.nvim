local size = require("mermaid-viewer.size")

local cell = { width = 10, height = 20 }

describe("mermaid-viewer.size", function()
  describe("inline", function()
    -- cell 20px high: at scale 1.0 a 24px natural line is one row, so natural px * 20/24
    local opts = { scale = 1.0, max_width = 1.0, max_height = 40 }

    it("keeps the natural size relative to the font", function()
      local cols, rows = size.inline({ width = 240, height = 120 }, opts, 100, 50, cell)
      assert.equals(20, cols) -- 200px
      assert.equals(5, rows) -- 100px
    end)

    it("scale multiplies the natural size", function()
      local cols, rows = size.inline({ width = 240, height = 120 }, { scale = 2, max_width = 1, max_height = 40 }, 100, 50, cell)
      assert.equals(40, cols)
      assert.equals(10, rows)
    end)

    it("shrinks tall diagrams to max_height, preserving aspect", function()
      local cols, rows = size.inline({ width = 240, height = 2400 }, opts, 100, 50, cell)
      assert.equals(40, rows)
      assert.equals(8, cols) -- 2000px high scaled to 800px: 200px * 0.4 = 80px
    end)

    it("shrinks wide diagrams to the text width, preserving aspect", function()
      local cols, rows = size.inline({ width = 2400, height = 240 }, opts, 50, 50, cell)
      assert.equals(50, cols)
      assert.equals(3, rows) -- 2000x200px scaled to 500px wide: 50px = 2.5 rows, rounded
    end)

    it("max_width <= 1 is a fraction of the text width, > 1 is cells", function()
      local cols = size.inline({ width = 2400, height = 240 }, { scale = 1, max_width = 0.5, max_height = 40 }, 100, 50, cell)
      assert.equals(50, cols)
      cols = size.inline({ width = 2400, height = 240 }, { scale = 1, max_width = 30, max_height = 40 }, 100, 50, cell)
      assert.equals(30, cols)
      cols = size.inline({ width = 2400, height = 240 }, { scale = 1, max_width = 300, max_height = 40 }, 100, 50, cell)
      assert.equals(100, cols) -- never wider than the text area
    end)

    it("max_height <= 1 is a fraction of the window height, > 1 is rows", function()
      local _, rows = size.inline({ width = 240, height = 2400 }, { scale = 1, max_width = 1, max_height = 0.5 }, 100, 30, cell)
      assert.equals(15, rows)
      _, rows = size.inline({ width = 240, height = 2400 }, { scale = 1, max_width = 1, max_height = 12 }, 100, 30, cell)
      assert.equals(12, rows)
    end)

    it("never goes below one row or column", function()
      local cols, rows = size.inline({ width = 10000, height = 1 }, opts, 5, 50, cell)
      assert.equals(5, cols)
      assert.equals(1, rows)
      cols, rows = size.inline({ width = 1, height = 10000 }, opts, 5, 50, cell)
      assert.equals(1, cols)
      assert.equals(40, rows)
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
