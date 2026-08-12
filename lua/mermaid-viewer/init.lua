---@class mermaid_viewer
local M = {}

---@param opts? mermaid_viewer.Options
function M.setup(opts)
  require("mermaid-viewer.config").setup(opts)
end

function M.view()
  local state = require("mermaid-viewer.state")
  if state.is_active() then
    return
  end

  local source = require("mermaid-viewer.source")
  local src, err = source.extract(0)
  if not src then
    vim.notify(err or "No mermaid diagram found", vim.log.levels.ERROR, { title = "mermaid-viewer" })
    return
  end

  local source_buf = vim.api.nvim_get_current_buf()

  local temp = require("mermaid-viewer.temp")
  temp.setup_exit_cleanup()

  local viewer = require("mermaid-viewer.viewer")
  local win, buf = viewer.open()

  local s = state.create(source_buf, win, buf)

  local navigation = require("mermaid-viewer.navigation")
  navigation.setup_keymaps(buf)

  local render = require("mermaid-viewer.render")
  local display = require("mermaid-viewer.display")
  local dims = viewer.get_dimensions()

  render.render(src, { width = dims.width * 100, height = dims.height * 100 }, function(render_err, png_path, temp_input)
    if temp_input then
      temp.track(temp_input)
    end
    if render_err then
      vim.notify(render_err, vim.log.levels.ERROR, { title = "mermaid-viewer" })
      return
    end
    if png_path then
      temp.track(png_path)
      display.show(png_path)
    end
  end)

  local config = require("mermaid-viewer.config")
  if config.options.auto_update then
    local debounce = require("mermaid-viewer.debounce")
    s.augroup = debounce.watch(source_buf, function()
      if not state.is_active() then
        return
      end

      local new_src = source.extract(s.source_buf)
      if not new_src then
        return
      end

      local current_dims = viewer.get_dimensions()
      if not current_dims then
        return
      end

      render.render(new_src, {
        width = math.floor(current_dims.width * 100 * s.zoom_level),
        height = math.floor(current_dims.height * 100 * s.zoom_level),
      }, function(re_err, re_path, re_input)
        if re_input then
          temp.track(re_input)
        end
        if re_err then
          return
        end
        if re_path then
          temp.track(re_path)
          display.show(re_path, {
            width = math.floor(current_dims.width * s.zoom_level),
            height = math.floor(current_dims.height * s.zoom_level),
          })
        end
      end)
    end)
  end
end

function M.close()
  local state = require("mermaid-viewer.state")
  if not state.is_active() then
    return
  end

  local s = state.current

  local display = require("mermaid-viewer.display")
  display.clear()

  if s.augroup ~= 0 then
    local debounce = require("mermaid-viewer.debounce")
    debounce.stop(s.augroup)
  end

  local viewer = require("mermaid-viewer.viewer")
  viewer.close()

  local temp = require("mermaid-viewer.temp")
  temp.cleanup()

  state.clear()
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
