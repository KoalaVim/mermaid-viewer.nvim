---@class mermaid_viewer.Render
local M = {}

local config = require("mermaid-viewer.config")

--- Render mermaid source to PNG asynchronously
---@param source string Mermaid diagram source text
---@param opts { width: number?, height: number? } Render dimensions in pixels
---@param callback fun(err: string|nil, png_path: string|nil, temp_input: string|nil)
function M.render(source, opts, callback)
  callback = vim.schedule_wrap(callback)

  local input_path = vim.fn.tempname() .. ".mmd"
  local output_path = vim.fn.tempname() .. ".png"

  local write_err = vim.fn.writefile(vim.split(source, "\n"), input_path)
  if write_err == -1 then
    callback("failed to write mermaid source to " .. input_path, nil, nil)
    return
  end

  local opt = config.options

  local cmd = {
    opt.mmdr_path,
    "-i",
    input_path,
    "-o",
    output_path,
    "-e",
    "png",
  }

  if opts.width then
    table.insert(cmd, "--width")
    table.insert(cmd, tostring(opts.width))
  end

  if opts.height then
    table.insert(cmd, "--height")
    table.insert(cmd, tostring(opts.height))
  end

  if opt.theme then
    table.insert(cmd, "--theme")
    table.insert(cmd, opt.theme)
  end

  if opt.fast_text then
    table.insert(cmd, "--fastText")
  end

  vim.system(cmd, { text = true }, function(result)
    if result.code ~= 0 then
      local err = result.stderr
      if err == nil or err == "" then
        err = "mmdr exited with code " .. result.code
      end
      callback(err, nil, input_path)
      return
    end

    callback(nil, output_path, input_path)
  end)
end

return M
