## Why

Neovim users working with Mermaid diagrams have no way to preview them without leaving the editor. Existing workflows require switching to a browser or external tool, breaking flow. We have two building blocks already available: `mmdr` (a fast Rust-based Mermaid renderer that outputs PNG/SVG) and `image.nvim` (a Neovim plugin that displays images via the Kitty graphics protocol). This plugin bridges them — render Mermaid source from a buffer and display the resulting diagram inline, with interactive zoom and pan so users can explore complex diagrams without leaving Neovim.

## What Changes

- New Neovim plugin `mermaid-viewer.nvim` that:
  - Detects Mermaid diagram source in the current buffer (`.mmd` files and fenced mermaid code blocks in Markdown)
  - Renders diagrams to PNG via the `mmdr` CLI
  - Displays the rendered image in a floating window using `image.nvim` and the Kitty graphics protocol
  - Supports interactive zoom in/out (re-renders at different scales or crops the view)
  - Supports panning/moving around the diagram via keyboard controls
  - Auto-updates the preview when the source buffer changes (debounced)
  - Provides user commands (`:MermaidView`, `:MermaidClose`) and configurable keymaps

## Capabilities

### New Capabilities

- `diagram-rendering`: Extracting Mermaid source from buffers, invoking `mmdr` to produce PNG output, and managing the render lifecycle (debounced re-renders on buffer change)
- `image-display`: Displaying rendered PNG in a Neovim floating window via `image.nvim`, handling positioning, sizing, and cleanup
- `interactive-navigation`: Zoom in/out and pan/move controls for exploring large diagrams within the viewer window
- `plugin-interface`: User commands, `<Plug>` keymaps, `setup()` configuration, and `:checkhealth` integration

### Modified Capabilities

(none — this is a new plugin)

## Impact

- **Dependencies**: Requires `mmdr` binary on PATH and `image.nvim` installed as a Neovim plugin. Requires a Kitty-protocol-compatible terminal.
- **New code**: Full Lua plugin under `lua/mermaid-viewer/`
- **File types**: Registers behavior for `.mmd` files and Markdown files containing mermaid code blocks
- **System calls**: Shells out to `mmdr` asynchronously via `vim.system()` or `vim.fn.jobstart()`
- **Temp files**: Writes rendered PNGs to a temp directory, cleaned up on close
