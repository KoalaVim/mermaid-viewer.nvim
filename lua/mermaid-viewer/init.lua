---@class mermaid_viewer
local M = {}

local NOTIFY_OPTS = { title = "mermaid-viewer" }

---@param msg string
---@param level? number
local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.ERROR, NOTIFY_OPTS)
end

---@param opts? mermaid_viewer.Options
function M.setup(opts)
  require("mermaid-viewer.config").setup(opts)
end

--- Bind the viewer to the diagram under the cursor (markdown and agent terminals; in markdown also from the line just
--- above a block, where its inline diagram is drawn) or the whole buffer (.mmd / mermaid)
---@param buf number
---@return mermaid_viewer.ViewerSource|nil
---@return string|nil err
local function resolve_source(buf)
  local source = require("mermaid-viewer.source")
  local viewer = require("mermaid-viewer.viewer")
  local kind = source.kind(buf)

  if kind == "markdown" or kind == "terminal" then
    local cursor = vim.api.nvim_win_get_cursor(0)[1] - 1
    -- the inline module also resolves the cursor sitting on a diagram or collapse marker
    local ok, inline = pcall(require, "mermaid-viewer.inline")
    local function block_at(row)
      if ok and type(inline.block_at) == "function" then
        local id = inline.block_at(buf, row)
        if id then
          return require("mermaid-viewer.blocks").get(buf, id)
        end
      end
      return source.block_at(buf, row)
    end
    local block = block_at(cursor)
    if not block and cursor + 1 < vim.api.nvim_buf_line_count(buf) then
      block = block_at(cursor + 1)
    end
    if not block then
      return nil, "No mermaid diagram found at cursor"
    end
    return { buf = buf, mark = viewer.anchor(buf, block.start_row) }
  end

  if kind == "mermaid" then
    local text, err = source.extract(buf)
    if not text then
      return nil, err
    end
    return { buf = buf }
  end
  return nil, "No mermaid diagram found"
end

---@param s mermaid_viewer.ViewerState
local function on_open(s)
  local state = require("mermaid-viewer.state")
  local viewer = require("mermaid-viewer.viewer")
  local config = require("mermaid-viewer.config")
  state.opening = nil
  state.set(s)

  require("mermaid-viewer.navigation").setup_keymaps(s.buf)
  require("mermaid-viewer.temp").setup_exit_cleanup()

  local group = vim.api.nvim_create_augroup("mermaid_viewer_float", { clear = true })
  s.group = group
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(s.win),
    callback = function()
      M.close(true)
    end,
  })
  vim.api.nvim_create_autocmd("WinScrolled", {
    group = group,
    pattern = tostring(s.win),
    callback = function()
      viewer.clamp_view(s)
    end,
  })
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = group,
    buffer = s.source.buf,
    callback = function()
      M.close()
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      M.close()
    end,
  })

  if config.options.auto_update then
    local cache = require("mermaid-viewer.cache")
    s.augroup = require("mermaid-viewer.debounce").watch(s.source.buf, function()
      if s.closed then
        return
      end
      local text = viewer.source_text(s.source)
      if text and cache.hash(text) == s.hash then
        return
      end
      viewer.refresh(s, {
        on_missing = function(err)
          M.close()
          notify(err .. "; viewer closed", vim.log.levels.WARN)
        end,
      })
    end, "viewer")
  end
end

function M.view()
  local state = require("mermaid-viewer.state")
  if state.is_active() or state.opening then
    return
  end

  local viewer = require("mermaid-viewer.viewer")
  local src, err = resolve_source(vim.api.nvim_get_current_buf())
  if not src then
    notify(err or "No mermaid diagram found")
    return
  end

  ---@type mermaid_viewer.ViewerState
  local s = {
    source = src,
    aspect = 1,
    cols = 0,
    rows = 0,
    zoom = 1.0,
    zoom_req = 1.0,
    gen = 0,
    closed = false,
  }
  state.opening = s

  local function fail(msg)
    if state.opening == s then
      state.opening = nil
    end
    s.closed = true
    viewer.release_anchor(src)
    notify(msg)
  end

  viewer.refresh(s, { on_open = on_open, on_missing = fail, on_error = fail })
end

--- Close the viewer: delete its images, stop auto-update, clear state. Also runs when the float is closed by
--- other means (`:q`, `<C-w>c`).
---@param from_win_closed? boolean the float window is already going away
function M.close(from_win_closed)
  local state = require("mermaid-viewer.state")
  if state.opening then
    state.opening.closed = true
    state.opening = nil
  end
  local s = state.current
  if not s then
    return
  end
  state.clear()
  s.closed = true

  if s.augroup then
    require("mermaid-viewer.debounce").stop(s.augroup)
  end
  if s.group then
    pcall(vim.api.nvim_del_augroup_by_id, s.group)
  end
  if s.key then
    local registry = require("mermaid-viewer.registry")
    registry.release(s.key)
    s.key, s.image = nil, nil
    -- zoomed renders may have pushed the inline images out of the terminal's image memory
    registry.retransmit_all()
  end

  local viewer = require("mermaid-viewer.viewer")
  viewer.release_anchor(s.source)
  if from_win_closed then
    s.win = nil
  else
    viewer.close_window(s)
  end
end

function M.toggle()
  local state = require("mermaid-viewer.state")
  if state.is_active() then
    M.close()
  else
    M.view()
  end
end

return M
