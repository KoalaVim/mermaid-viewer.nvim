## Why

Today a diagram is only visible after explicitly opening the floating viewer, and the viewer draws images at fixed screen coordinates. That approach can't follow buffer scrolling, isn't clipped by windows, overlaps text depending on z-index, and fights the TUI for the cursor — which made inline rendering impossible and produced a string of viewer bugs (image spilling past the float, stale state after `:q`, zoom/auto-update looking at the wrong window's cursor). Reading a markdown document with diagrams should show the diagrams in place, with the float reserved for exploring a single diagram in detail.

## What Changes

- Render every ` ```mermaid ` block in a markdown buffer inline, as virtual lines directly above the opening fence. On by default; toggle per buffer with `:MermaidInline`; disable globally via config.
- Inline diagrams have a fixed maximum height in rows (configurable); width follows the diagram's aspect ratio and is reduced if it would exceed the window width.
- Blocks can be collapsed to a single `··· N lines (mermaid)` marker below the diagram. A collapsed block stays collapsed in normal mode and expands when entering insert or visual mode on it.
- Inline diagrams re-render (debounced) when their block's source changes; unchanged blocks are served from a cache.
- **BREAKING** (behavioral): Switch all image display — inline and float — to Kitty virtual placements with Unicode placeholder characters. Images become buffer text: they scroll, fold and clip with Neovim windows. Terminals without placeholder support (e.g. WezTerm) are no longer supported.
- The floating viewer (`<leader>um` / `:MermaidView`) shows the diagram for the block under the cursor (including when the cursor is on its inline diagram or collapse marker) as a nowrap buffer of placeholder lines. Moving around uses native motions (`hjkl`, `zh`/`zl`, `<C-d>`/`<C-u>`, mouse wheel); only zoom (`+`/`-`/`0`) keeps custom keys.
- **BREAKING**: Remove the custom pan keymaps and `pan_step` option.
- The viewer stays bound to the block it was opened for, so zoom and auto-update keep working after focus moves into the float. Closing the float any way (`q`, `<Esc>`, `:q`, `<C-w>c`) fully tears down viewer state.
- Remove the stale `image.nvim` references from specs and health checks; health checks verify placeholder support instead.

## Capabilities

### New Capabilities
- `inline-rendering`: Rendering mermaid blocks inline in markdown buffers — placement above the fence, sizing, per-buffer toggle, collapse/expand behavior, and keeping inline images in sync with edits.

### Modified Capabilities
- `diagram-rendering`: Source extraction binds to a specific block instead of the current window's cursor; render size derives from the terminal cell pixel size within terminal limits; theme comes from config; rendered images are cached by content instead of per-viewer temp files.
- `image-display`: Images are displayed through Kitty Unicode placeholders inside buffers rather than at screen coordinates; the float hosts a placeholder grid; viewer state is torn down however the float is closed.
- `interactive-navigation`: Panning is replaced by native buffer motions in the viewer; zoom re-renders the placeholder grid and is bounded by the placeholder grid limit.
- `plugin-interface`: Adds `:MermaidInline` and collapse toggle, inline/collapse config options, viewer opening from inline diagrams; health check drops `image.nvim` and checks placeholder support; pan keymap options removed.

## Impact

- **Code**: `lua/mermaid-viewer/kitty.lua` (virtual placements + placeholder grid), `display.lua` / `viewer.lua` (float as placeholder buffer), `navigation.lua` (zoom only), `source.lua` (block-bound extraction), new `inline.lua` (block scan, extmarks, collapse), `health.lua`, `config.lua`, `plugin/mermaid-viewer.lua`.
- **Terminals**: Requires Unicode placeholder support (Kitty, Ghostty; herdr to be verified). WezTerm loses support.
- **Neovim**: Uses `nvim_ui_send` (0.12+) for terminal output and extmark `conceal_lines` (0.11+) or folds for collapsing.
- **Interplay**: Shares markdown buffers with render-markdown.nvim (fence styling, `conceallevel`/`concealcursor`).
- **Config**: New `inline` options; removed `pan_step` and pan keys.
