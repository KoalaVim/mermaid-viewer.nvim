---@class mermaid_viewer.Render
local M = {}

local config = require("mermaid-viewer.config")
local cache = require("mermaid-viewer.cache")
local png = require("mermaid-viewer.png")
local size = require("mermaid-viewer.size")
local temp = require("mermaid-viewer.temp")

---@param input_path string
---@param output_path string
---@param width number|nil
---@param height number|nil
---@return string[]
local function build_cmd(input_path, output_path, width, height)
  local opt = config.options
  local cmd = { opt.mmdr_path, "-i", input_path, "-o", output_path, "-e", "png" }

  if width then
    vim.list_extend(cmd, { "--width", tostring(width) })
  end
  if height then
    vim.list_extend(cmd, { "--height", tostring(height) })
  end
  if opt.theme then
    vim.list_extend(cmd, { "--theme", opt.theme })
  end
  if opt.fast_text then
    table.insert(cmd, "--fastText")
  end
  return cmd
end

---@param result vim.SystemCompleted
---@return string
local function error_message(result)
  local err = result.stderr
  if err == nil or err == "" then
    err = "mmdr exited with code " .. result.code
  end
  return err
end

--- Render mermaid source to a fresh temp PNG asynchronously (uncached)
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

  vim.system(build_cmd(input_path, output_path, opts.width, opts.height), { text = true }, function(result)
    if result.code ~= 0 then
      callback(error_message(result), nil, input_path)
      return
    end
    callback(nil, output_path, input_path)
  end)
end

---@type table<string, fun(err: string|nil, path: string|nil)[]>
local pending = {}

--- Render through the cache. Identical in-flight requests share one mmdr run; the temp input is deleted afterwards.
--- Width and height must both be given or both be nil (natural size).
---@param source string
---@param opts { width: number?, height: number? }
---@param callback fun(err: string|nil, png_path: string|nil)
function M.cached(source, opts, callback)
  local key = cache.key(cache.hash(source), opts.width, opts.height, config.options.theme)
  local hit = cache.lookup(key)
  if hit then
    vim.schedule(function()
      callback(nil, hit)
    end)
    return
  end

  if pending[key] then
    table.insert(pending[key], callback)
    return
  end
  pending[key] = { callback }

  local function finish(err, path)
    local callbacks = pending[key]
    pending[key] = nil
    vim.schedule(function()
      for _, cb in ipairs(callbacks) do
        cb(err, path)
      end
    end)
  end

  local output_path = cache.path(key)
  local input_path = output_path:gsub("%.png$", ".mmd")
  if vim.fn.writefile(vim.split(source, "\n"), input_path) == -1 then
    finish("failed to write mermaid source to " .. input_path, nil)
    return
  end

  vim.system(build_cmd(input_path, output_path, opts.width, opts.height), { text = true }, function(result)
    os.remove(input_path)
    if result.code ~= 0 then
      os.remove(output_path)
      finish(error_message(result), nil)
      return
    end
    finish(nil, output_path)
  end)
end

---@class mermaid_viewer.DiagramResult
---@field path string
---@field width_px number Actual PNG width
---@field height_px number Actual PNG height
---@field aspect number Diagram width / height
---@field cols number Target grid columns
---@field rows number Target grid rows

--- Render a diagram sized to a cell grid. Learns the aspect ratio with a cached natural-size render if unknown,
--- then renders at the target pixel size (reusing the natural render when within 10% of the target).
---@param source string
---@param target { cols: number, rows: number }|fun(aspect: number): number, number Fixed grid, or computes cols, rows from the aspect
---@param callback fun(err: string|nil, result: mermaid_viewer.DiagramResult|nil)
function M.diagram(source, target, callback)
  local hash = cache.hash(source)

  local function sized(natural_path, nw, nh)
    local aspect = cache.get_aspect(hash)
    local cols, rows
    if type(target) == "function" then
      cols, rows = target(aspect)
    else
      cols, rows = target.cols, target.rows
    end
    local cell = require("mermaid-viewer.kitty").cell_size()
    local w, h = size.pixels(cols, rows, cell)

    local function done(err, path)
      if err then
        return callback(err, nil)
      end
      local pw, ph = png.dimensions(path)
      callback(nil, { path = path, width_px = pw or w, height_px = ph or h, aspect = aspect, cols = cols, rows = rows })
    end

    if natural_path and math.abs(nw - w) <= 0.1 * w and math.abs(nh - h) <= 0.1 * h then
      return vim.schedule(function()
        done(nil, natural_path)
      end)
    end
    M.cached(source, { width = w, height = h }, done)
  end

  local natural_key = cache.key(hash, nil, nil, config.options.theme)
  local known = cache.get_aspect(hash)
  local natural = cache.lookup(natural_key)
  if known and not natural then
    return sized()
  end

  M.cached(source, {}, function(err, path)
    if err then
      return callback(err, nil)
    end
    local nw, nh = png.dimensions(path)
    if not nw then
      return callback("could not read rendered PNG: " .. tostring(nh), nil)
    end
    cache.set_aspect(hash, nw / nh)
    sized(path, nw, nh)
  end)
end

return M
