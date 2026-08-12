## Context

This is a greenfield Neovim plugin. Two key dependencies already exist:

- **`mmdr`** (mermaid-rs-renderer): A Rust CLI that renders Mermaid diagrams to SVG or PNG. Extremely fast (100-1400x over mermaid-cli). Accepts input via file or stdin, outputs to file or stdout. Supports `--width`/`--height` for sizing, `--theme` for styling, and `--outputFormat png` for raster output.
- **`image.nvim`**: A Neovim plugin that displays images inside Neovim using the Kitty graphics protocol. Provides `from_file(path, opts)` to create images, `image:render()`, `image:move(x,y)`, `image:clear()`, and size/position options. Supports binding images to windows. The Kitty backend clips images to window boundaries natively.

The plugin targets users working with Mermaid diagrams in Neovim on Kitty-protocol-compatible terminals.

## Goals / Non-Goals

**Goals:**
- Render Mermaid source from the current buffer and display the result in a floating window
- Support `.mmd` files and fenced mermaid code blocks in Markdown
- Provide interactive zoom (in/out) and pan (directional movement) via keyboard
- Auto-update the preview when the source changes
- Work out of the box with minimal configuration

**Non-Goals:**
- Editing diagrams visually (this is view-only)
- Supporting non-Kitty terminals (ueberzug/sixel backends are out of scope for v1)
- Mouse-based interactions (keyboard only for v1)
- Rendering multiple diagrams simultaneously
- Live-preview-as-you-type (updates are debounced, not keystroke-level)

## Decisions

### 1. Rendering pipeline: shell out to `mmdr` CLI

Render Mermaid source to PNG by invoking `mmdr -i <input> -o <output> -e png --width <w> --height <h>` asynchronously via `vim.system()`.

**Why not SVG?** image.nvim displays raster images. SVG would need an extra rasterization step. `mmdr` handles SVG→PNG internally via resvg when `-e png` is used, so we get a single-step pipeline.

**Why CLI, not library?** mmdr is a Rust binary — calling it as a subprocess is the natural integration point from Lua. `vim.system()` provides async execution without blocking the editor.

### 2. Zoom via re-render at different resolutions

When the user zooms in/out, re-render the diagram at a different `--width`/`--height` and redisplay.

**Why re-render instead of image scaling?** mmdr is fast enough (~5-50ms per render) that re-rendering produces sharp output at every zoom level. Image scaling in the terminal would produce blurry results. The Kitty protocol can scale images, but vector-quality re-rendering is superior for diagrams.

**Alternatives considered:**
- *Render once at high resolution, crop to viewport*: Would require either extending image.nvim's API to expose Kitty crop parameters, or writing a custom Kitty protocol layer. More complex for marginal benefit given mmdr's speed.
- *Scale the terminal cell size*: Kitty's display scaling produces blurry text on diagrams.

### 3. Pan via viewport offset tracking

Maintain a virtual viewport (x_offset, y_offset) into the diagram. When panning, adjust the offset and re-render with `mmdr` using a shifted view, or render at a larger size and position the image.nvim image so the desired region aligns with the floating window. The window boundary clips the overflow naturally.

The approach: render at `zoom_level * base_size`, then use `image:move()` to position the image within the floating window so the viewport offset region is visible. image.nvim's Kitty backend clips to window boundaries.

### 4. Floating window as the viewer container

Open a Neovim floating window (via `vim.api.nvim_open_win`) to host the diagram. The float:
- Has a configurable size (default: 80% of editor width/height)
- Is non-focusable for the buffer but receives keymap inputs
- Uses a scratch buffer with `bufhidden=wipe`
- The image.nvim image is bound to this window

**Why a float, not a split?** Diagrams are auxiliary content — a float overlays without rearranging the user's layout. The user dismisses it and returns to exactly where they were.

### 5. Source extraction strategy

- **`.mmd` files**: Entire buffer content is the diagram source.
- **Markdown files**: Extract the fenced code block under the cursor (` ```mermaid ... ``` `). Use treesitter if available to locate the code block, fall back to line scanning.
- Pass the extracted source to mmdr via a temp file (not stdin) to avoid shell escaping issues on Windows.

### 6. Debounced auto-update

Attach a `BufWritePost` autocmd (and optionally `TextChanged`/`TextChangedI` with debounce) to re-render when the source changes. Default debounce: 300ms. The preview updates after the user stops typing, not on every keystroke.

### 7. Temp file management

Rendered PNGs are written to `vim.fn.tempname()` paths. A registry tracks all temp files per viewer session. On viewer close, all temp files are deleted. On Neovim exit (`VimLeavePre`), any remaining temp files are cleaned up.

## Risks / Trade-offs

**[`mmdr` not installed]** → `:checkhealth` validates `mmdr` is on PATH and reports the version. Clear error message on first use if missing, with install instructions.

**[image.nvim not installed or not configured for Kitty]** → `:checkhealth` validates image.nvim is loadable and backend is Kitty. Fail gracefully with actionable error.

**[Re-render on zoom may flicker]** → Double-buffer: render the new image to a new temp file, swap display only when ready, then clear the old image. This avoids a visible clear→render gap.

**[Large diagrams may render slowly]** → mmdr's `--fastText` flag trades font accuracy for speed. Expose as a config option. For very large diagrams, show a "rendering..." indicator.

**[Pan with image:move() may not support negative coordinates]** → If image.nvim's move() doesn't support positioning the image above/left of the window origin, we'll need to either: (a) use a larger float and reposition it, or (b) render only the visible viewport region. Investigate during implementation.

**[Windows path handling]** → Use `vim.fn.shellescape()` and forward slashes for temp paths passed to mmdr.
