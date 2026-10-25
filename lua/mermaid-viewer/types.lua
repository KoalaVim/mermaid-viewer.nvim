---@alias mermaid_viewer.Theme "default"|"dark"|"forest"|"neutral"|"modern"

---@class mermaid_viewer.FloatOptions
---@field width? number Percentage of editor width (0.0-1.0)
---@field height? number Percentage of editor height (0.0-1.0)
---@field border? string|string[] Border style for the float window
---@field win_config? vim.api.keyset.win_config Passed to nvim_open_win, overriding the computed size, position and style

---@class mermaid_viewer.KeyOptions
---@field zoom_in? string Keymap to zoom in
---@field zoom_out? string Keymap to zoom out
---@field zoom_reset? string Keymap to reset zoom
---@field close? string[] Keymaps to close the viewer

---@class mermaid_viewer.TerminalOptions
---@field placeholders? boolean Override Unicode placeholder support detection (nil = detect from TERM_PROGRAM/TERM)

---@class mermaid_viewer.InlineOptions
---@field enabled? boolean Render mermaid blocks inline in markdown buffers (toggle per buffer with :MermaidInline)
---@field scale? number Diagram size relative to the editor font (1.0 = diagram text about as large as buffer text)
---@field max_width? number Max width: <= 1 is a fraction of the window's text width, > 1 is cells
---@field max_height? number Max height: <= 1 is a fraction of the window height, > 1 is rows

---@class mermaid_viewer.Options
---@field mmdr_path? string Path to mmdr binary
---@field theme? mermaid_viewer.Theme Mermaid theme
---@field debounce_ms? number Debounce delay for re-renders
---@field fast_text? boolean Use mmdr --fastText for speed
---@field float? mermaid_viewer.FloatOptions Floating window options
---@field keys? mermaid_viewer.KeyOptions Keymap overrides
---@field auto_update? boolean Auto-update on source change
---@field zoom_step? number Multiplier per zoom step
---@field max_zoom? number Maximum zoom level
---@field debug? boolean Send graphics with terminal replies enabled and log them (vim.notify at DEBUG level)
---@field terminal? mermaid_viewer.TerminalOptions Terminal capability overrides
---@field inline? mermaid_viewer.InlineOptions Inline rendering options

---@class mermaid_viewer.InternalConfig
---@field mmdr_path string
---@field theme mermaid_viewer.Theme
---@field debounce_ms number
---@field fast_text boolean
---@field float { width: number, height: number, border: string|string[], win_config: vim.api.keyset.win_config }
---@field keys { zoom_in: string, zoom_out: string, zoom_reset: string, close: string[] }
---@field auto_update boolean
---@field zoom_step number
---@field max_zoom number
---@field debug boolean
---@field terminal { placeholders: boolean|nil }
---@field inline { enabled: boolean, scale: number, max_width: number, max_height: number }

---@class mermaid_viewer.ViewerSource
---@field buf number Source buffer handle
---@field mark? number Anchor extmark on the block's opening fence (nil = the whole buffer is the diagram)

---@class mermaid_viewer.ViewerState
---@field source mermaid_viewer.ViewerSource
---@field win number Float window handle
---@field buf number Float buffer handle
---@field image mermaid_viewer.Image|nil Image currently displayed (holds one registry reference)
---@field hash string|nil Hash of the displayed source
---@field aspect number Diagram width / height
---@field cols number Displayed grid columns
---@field rows number Displayed grid rows
---@field zoom number Displayed zoom level (1.0 = fit)
---@field zoom_req number Requested zoom level (zoom steps start from it)
---@field gen number Render generation; results of older requests are dropped
---@field augroup number|nil Autocmd group id of the auto-update watcher
---@field group number|nil Autocmd group id of the float lifecycle autocmds
---@field key string|nil Registry key of the displayed image
---@field closed boolean
