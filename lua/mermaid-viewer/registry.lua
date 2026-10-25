local kitty = require("mermaid-viewer.kitty")
local terminal = require("mermaid-viewer.terminal")

--- Refcounted Kitty images. Image ids are global to the terminal, so ids come from a random 24-bit base per
--- Neovim instance. This is also the gate for graphics output: nothing is transmitted on unsupported terminals.
---@class mermaid_viewer.Registry
local M = {}

---@class mermaid_viewer.Image
---@field key string
---@field id number
---@field cols number
---@field rows number
---@field hl string
---@field path string PNG the image was transmitted from
---@field refcount number

local MAX_ID = 0xFFFFFF

---@type table<string, mermaid_viewer.Image>
local images = {}
---@type table<number, boolean>
local used_ids = {}
local next_id

local function init_base()
  math.randomseed(vim.uv.hrtime() % 2147483647)
  next_id = math.random(1, MAX_ID - 0x10000)
end

---@return number
local function alloc_id()
  if not next_id then
    init_base()
  end
  repeat
    next_id = next_id >= MAX_ID and 1 or next_id + 1
  until not used_ids[next_id]
  return next_id
end

--- Take a reference on the image for `key`, transmitting it first if it is not in the terminal yet.
--- Acquire a replacement before releasing the old image so the swap never shows a gap.
---@param key string cache key (source hash + size + theme)
---@param png_path string
---@param cols number
---@param rows number
---@return mermaid_viewer.Image|nil image nil when graphics are unavailable (reason in second return)
---@return string|nil err
function M.acquire(key, png_path, cols, rows)
  local img = images[key]
  if img then
    img.refcount = img.refcount + 1
    return img
  end
  if not terminal.check() then
    return nil, "terminal does not support Kitty Unicode placeholders"
  end

  cols = math.min(cols, kitty.max_cells)
  rows = math.min(rows, kitty.max_cells)
  local id = alloc_id()
  if not kitty.transmit_virtual(png_path, id, cols, rows) then
    return nil, "cannot read " .. png_path
  end
  used_ids[id] = true
  img = { key = key, id = id, cols = cols, rows = rows, hl = kitty.set_highlight(id), path = png_path, refcount = 1 }
  images[key] = img
  return img
end

--- Drop a reference; the image is deleted from the terminal when the last one goes.
---@param key string
function M.release(key)
  local img = images[key]
  if not img then
    return
  end
  img.refcount = img.refcount - 1
  if img.refcount > 0 then
    return
  end
  images[key] = nil
  used_ids[img.id] = nil
  kitty.delete_image(img.id)
  kitty.clear_highlight(img.id)
end

---@param key string
---@return mermaid_viewer.Image|nil
function M.get(key)
  return images[key]
end

--- Send every live image to the terminal again under its id. Terminals evict old images when big ones (zoomed
--- viewer renders) fill their image memory; re-sending restores the inline diagrams without re-rendering.
function M.retransmit_all()
  for _, img in pairs(images) do
    kitty.transmit_virtual(img.path, img.id, img.cols, img.rows)
  end
end

--- Release everything regardless of refcount (VimLeavePre)
function M.release_all()
  for key, img in pairs(images) do
    img.refcount = 1
    M.release(key)
  end
end

--- Reset module state without touching the terminal (tests)
---@param base? number force the id allocation base
function M._reset(base)
  images = {}
  used_ids = {}
  next_id = base
end

return M
