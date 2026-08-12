## 1. Project Scaffolding

- [x] 1.1 Scaffold the plugin directory structure (`lua/mermaid-viewer/`, `plugin/`, `doc/`, `tests/`) following neovim-plugin-init conventions
- [x] 1.2 Create config module (`lua/mermaid-viewer/config.lua`) with default options: theme, debounce_ms, float size/border, keymaps, mmdr_path, fast_text
- [x] 1.3 Create types module (`lua/mermaid-viewer/types.lua`) with LuaCATS annotations for all config and internal types

## 2. Diagram Rendering

- [x] 2.1 Create render module (`lua/mermaid-viewer/render.lua`) with async `mmdr` invocation via `vim.system()` — accepts source string, output path, render options; returns via callback
- [x] 2.2 Implement source extraction (`lua/mermaid-viewer/source.lua`) — full buffer for `.mmd` files, treesitter-based fenced block extraction for Markdown (with line-scan fallback)
- [x] 2.3 Implement temp file management — generate temp paths for input/output, track per session, cleanup on close and VimLeavePre
- [x] 2.4 Implement debounced re-render — attach TextChanged/TextChangedI autocmds with configurable debounce timer using `vim.defer_fn`, cancel pending renders on new edits

## 3. Image Display

- [x] 3.1 Create viewer module (`lua/mermaid-viewer/viewer.lua`) — manages the floating window lifecycle (open, close, resize), scratch buffer with `bufhidden=wipe`
- [x] 3.2 Integrate image.nvim — use `require("image").from_file()` to load PNG, bind to the float window, handle initial fit-to-window sizing
- [x] 3.3 Implement double-buffered image swap — on re-render, create new image from new file, render it, then clear old image to avoid flicker
- [x] 3.4 Handle viewer state tracking — single active viewer instance, track source buffer / float window / current image / zoom level / pan offset

## 4. Interactive Navigation

- [x] 4.1 Implement zoom state management — zoom_level (1.0x to 5.0x), zoom_steps list, current index; compute render dimensions from zoom level and float size
- [x] 4.2 Implement zoom in/out actions — re-render at new dimensions via mmdr, update displayed image, maintain viewport center
- [x] 4.3 Implement zoom reset action — return to 1.0x, re-render at fit-to-window size
- [x] 4.4 Implement pan state and actions — track x/y viewport offset, shift by configurable step on h/j/k/l or arrow keys, clamp to image bounds, reposition image via `image:move()`
- [x] 4.5 Set up buffer-local keymaps on the float buffer — bind zoom/pan/close keys, make keymaps configurable via setup()

## 5. Plugin Interface

- [x] 5.1 Create init module (`lua/mermaid-viewer/init.lua`) — expose `setup(opts)`, `view()`, `close()`, `toggle()` as the public API
- [x] 5.2 Create plugin file (`plugin/mermaid-viewer.lua`) — register `:MermaidView`, `:MermaidClose`, `:MermaidToggle` user commands; define `<Plug>(mermaid-viewer-view)`, `<Plug>(mermaid-viewer-close)`, `<Plug>(mermaid-viewer-toggle)` mappings
- [x] 5.3 Implement health check (`lua/mermaid-viewer/health.lua`) — validate mmdr on PATH (report version), validate image.nvim loadable, check terminal Kitty support

## 6. Testing and Polish

- [x] 6.1 Write busted tests for source extraction — .mmd full buffer, markdown block extraction, no-block-at-cursor error case
- [x] 6.2 Write busted tests for config merging — defaults, partial overrides, deep merge of nested tables
- [ ] 6.3 Manual integration test — open a .mmd file, trigger viewer, zoom in/out, pan, edit source and verify auto-update, close viewer
- [x] 6.4 Add dotfiles (stylua.toml, selene.toml, .editorconfig, .luarc.json) and format all Lua files with StyLua
