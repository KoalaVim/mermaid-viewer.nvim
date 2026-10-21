local png = require("mermaid-viewer.png")

local function be32(n)
  return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
end

describe("mermaid-viewer.png", function()
  it("parses IHDR width and height", function()
    local bytes = "\137PNG\r\n\26\n" .. be32(13) .. "IHDR" .. be32(305) .. be32(1038) .. "rest"
    local w, h = png.parse_header(bytes)
    assert.equals(305, w)
    assert.equals(1038, h)
  end)

  it("rejects non-PNG data", function()
    local w, err = png.parse_header("hello world, this is not a png file")
    assert.is_nil(w)
    assert.equals("not a PNG", err)
  end)

  it("matches `file` for a real natural-size mmdr render", function()
    if vim.fn.executable("mmdr") == 0 or vim.fn.executable("file") == 0 then
      return
    end
    local out = vim.fn.tempname() .. ".png"
    vim.fn.system({ "mmdr", "-i", "test-files/flowchart.mmd", "-o", out, "-e", "png" })
    assert.equals(0, vim.v.shell_error)
    local w, h = png.dimensions(out)
    local info = vim.fn.system({ "file", out })
    local fw, fh = info:match("(%d+) x (%d+)")
    os.remove(out)
    assert.equals(tonumber(fw), w)
    assert.equals(tonumber(fh), h)
  end)
end)
