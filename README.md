# mermaid-viewer.nvim

See Mermaid diagrams inside Neovim: rendered inline above every ` ```mermaid ` block in Markdown, and in a floating viewer you can zoom and move around. Renders diagrams using [mmdr](https://github.com/mermaid-rs/mermaid-rs) and displays them via the [Kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/) with Unicode placeholders.

## Requirements

- Neovim >= 0.12
- [mmdr](https://github.com/mermaid-rs/mermaid-rs) - Fast Mermaid renderer written in Rust
- A terminal that supports Kitty graphics Unicode placeholders: [Kitty](https://sw.kovidgoyal.net/kitty/), [Ghostty](https://ghostty.org/), or [herdr](https://herdr.dev/) running in one of them. WezTerm is not supported (no placeholder support).
- `termguicolors` enabled (placeholders encode the image id in the text color)

### Installing mmdr

```sh
cargo install mermaid-rs-renderer
```

Or see the [mmdr installation docs](https://github.com/mermaid-rs/mermaid-rs#installation) for Homebrew, Scoop, AUR, and Nix options.

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "KoalaVim/mermaid-viewer.nvim",
  cmd = { "MermaidView", "MermaidClose", "MermaidToggle", "MermaidInline", "MermaidCollapse" },
  ft = { "markdown", "mermaid" },
  keys = {
    { "<leader>um", "<cmd>MermaidToggle<cr>", ft = { "markdown", "mermaid" }, desc = "Mermaid Viewer" },
    { "<leader>ui", "<cmd>MermaidInline<cr>", ft = "markdown", desc = "Toggle inline mermaid" },
    { "<leader>uc", "<cmd>MermaidCollapse<cr>", ft = "markdown", desc = "Collapse mermaid block" },
  },
  opts = {},
}
```

## Inline rendering

In markdown buffers every ` ```mermaid ` block is rendered in place, as a picture directly above the block's opening
fence. The picture is made of Kitty Unicode placeholder characters, so it behaves like buffer text: it scrolls with the
buffer, is clipped to its window and shows in each window that displays the block. The buffer text is never modified.

- Only blocks that are on screen (plus one screen above and below) are rendered; the rest render when you scroll to
  them. Rendered diagrams are cached, so scrolling back never renders again.
- Editing a block re-renders only that block, after `debounce_ms`. The old picture stays until the new one is ready, so
  there is no blank gap.
- If a block fails to render, a one-line error (the first line of the `mmdr` message, truncated to the window width) is
  shown above the fence instead of a picture, with no notification per keystroke. It is replaced by the diagram once the
  syntax is fixed.
- Non-mermaid code blocks are ignored. `.mmd` buffers are not rendered inline; use `:MermaidView` for them.

Each diagram is scaled to `inline.height` rows; its width follows the diagram's aspect ratio. If that would be wider
than the window's text area, the diagram is scaled down to fit the width (and gets fewer rows).

Set `inline = { enabled = false }` to open markdown buffers without diagrams; `:MermaidInline` still enables them for
the current buffer.

| Command / mapping                      | Action                                                 |
| -------------------------------------- | ------------------------------------------------------ |
| `:MermaidInline`                       | Toggle inline rendering in the current markdown buffer |
| `<Plug>(mermaid-viewer-inline-toggle)` | Same, for use in your own mappings                     |

Turning it off removes all diagrams and collapse markers from that buffer (collapsed blocks become visible again) and
frees their images; other buffers are unaffected. Turning it on again renders every block. On a non-markdown buffer the
command only shows "inline rendering applies to markdown buffers only".

### Collapsing blocks

A block can be collapsed so only its diagram remains: its source lines (fences included) are hidden and a single marker
`··· N lines (mermaid)` is shown below the diagram.

| Command / mapping                        | Action                                        |
| ---------------------------------------- | --------------------------------------------- |
| `:MermaidCollapse`                       | Collapse or expand the block under the cursor |
| `<Plug>(mermaid-viewer-collapse-toggle)` | Same, for use in your own mappings            |

The cursor can be anywhere on the block, on its fences, or on the line its diagram and marker hang from (the line
after a collapsed block). With no block there, `No mermaid diagram found at cursor` is shown.

A collapsed block stays collapsed while you move over it in normal mode. Entering insert or visual mode with the cursor
on it expands it so you can edit; once you are back in normal mode and the cursor has left the block, it collapses
again.

Collapsing uses Neovim's `conceal_lines`, which needs `conceallevel` above 0. While a buffer has collapsed blocks the
plugin sets `conceallevel=2` (only if it was 0) and adds `n` to `concealcursor` in the windows showing it, and restores
both when nothing is collapsed any more. Collapsed state is per session and is not saved.

## Viewer

`:MermaidView` opens a floating window with the diagram for the block under the cursor (markdown: the fenced block you
are in, including its inline diagram or collapse marker; `.mmd`/`mermaid` buffers: the whole buffer). The diagram is
plain buffer text inside the float and is clipped by it.

| Command          | Description       |
| ---------------- | ----------------- |
| `:MermaidView`   | Open the viewer   |
| `:MermaidClose`  | Close the viewer  |
| `:MermaidToggle` | Toggle the viewer |

At 1.0x the whole diagram fits in the float. Zoom in and the float becomes a scrollable canvas that you move around with
Neovim's own motions: `h` `j` `k` `l`, `zh`/`zl`/`zH`/`zL`, `<C-d>`/`<C-u>`, `<C-e>`/`<C-y>`, `gg`/`G`, and the mouse
wheel. The view stops at the diagram's edges.

| Key (default) | Action                                                   |
| ------------- | -------------------------------------------------------- |
| `+` / `=`     | Zoom in (`keys.zoom_in`; `=` is added when it is `+`)    |
| `-`           | Zoom out (`keys.zoom_out`)                               |
| `0`           | Reset to 1.0x, view at the top-left (`keys.zoom_reset`) |
| `q` / `<Esc>` | Close (`keys.close`)                                     |

Zoom keeps the cell in the middle of the view centered, and stops at `max_zoom` (default 5.0) or when the diagram would
exceed 297 cells on a side. Editing the block while the viewer is open re-renders it (`auto_update`, debounced by
`debounce_ms`), also with focus in the float. Closing the float any way (`q`, `:q`, `<C-w>c`) removes the image.

### Plug mappings

```lua
vim.keymap.set("n", "<leader>um", "<Plug>(mermaid-viewer-toggle)")
vim.keymap.set("n", "<leader>uM", "<Plug>(mermaid-viewer-view)")
vim.keymap.set("n", "<leader>ui", "<Plug>(mermaid-viewer-inline-toggle)")
vim.keymap.set("n", "<leader>uc", "<Plug>(mermaid-viewer-collapse-toggle)")
```

## Configuration

The plugin works out of the box with no configuration. Call `setup()` only to override defaults:

```lua
require("mermaid-viewer").setup({
  mmdr_path = "mmdr",       -- path to mmdr binary
  theme = "default",        -- mermaid theme for every render: "default", "dark", "forest", "neutral", "modern"
  debounce_ms = 300,        -- delay before re-rendering after an edit (inline and viewer)
  fast_text = false,        -- use mmdr --fastText for faster rendering
  auto_update = true,       -- re-render the viewer when its block changes

  inline = {
    enabled = true,         -- render markdown buffers inline automatically
    height = 15,            -- inline diagram height in rows
  },

  float = {
    width = 0.8,            -- max float width as percentage of editor (0.0-1.0)
    height = 0.8,           -- max float height as percentage of editor (0.0-1.0)
    border = "rounded",     -- border style
    win_config = {},        -- passed to nvim_open_win, overriding the computed config (see below)
  },

  keys = {
    zoom_in = "+",
    zoom_out = "-",
    zoom_reset = "0",
    close = { "q", "<Esc>" },
  },

  zoom_step = 1.5,          -- zoom multiplier per step
  max_zoom = 5.0,           -- maximum zoom level

  terminal = {
    placeholders = nil,     -- nil = detect; true/false to force Unicode placeholder support on or off
  },
  debug = false,            -- send graphics with terminal replies enabled and log them
})
```

### Viewer window

The viewer float is opened with `nvim_open_win`. By default it is centered, sized to the diagram (at most
`float.width` × `float.height` of the editor), `style = "minimal"`, with `float.border`. Anything in
`float.win_config` is merged over that config, both when the window opens and when zoom resizes it, so you control
the window with the regular `:h nvim_open_win()` keys:

```lua
require("mermaid-viewer").setup({
  float = {
    win_config = {
      title = " Mermaid ",
      title_pos = "center",
      footer = " +/- zoom · 0 reset · q close ",
      footer_pos = "right",
      zindex = 60,
      -- pin it instead of centering it:
      -- relative = "editor", anchor = "NE", row = 1, col = vim.o.columns - 1,
      -- fixed size in cells; the diagram is fitted to it instead of float.width/height:
      -- width = 100, height = 30,
    },
  },
})
```

`width` and `height` in `win_config` are in cells and fix the window size; `float.width` / `float.height` are
fractions of the editor and only cap the size of a window sized to the diagram.

**Removed options:** `pan_step` and `keys.pan_up`/`pan_down`/`pan_left`/`pan_right` no longer exist; use the native
motions above. Passing them to `setup()` logs one warning and they are ignored.

## Health check

Run `:checkhealth mermaid-viewer` to verify Neovim, `mmdr`, `termguicolors` and terminal placeholder support.

## How it works

1. Finds ` ```mermaid ` blocks with treesitter (line scan fallback) and anchors each with an extmark, so blocks keep
   their identity as you edit around them
2. Renders to PNG via `mmdr` asynchronously, sized from the terminal's real cell size; results are cached by source,
   size and theme
3. Transmits each PNG once to the terminal as a Kitty virtual placement, then draws it with Unicode placeholder
   characters: as virtual lines above the fence inline, and as buffer lines in the viewer float
4. Re-renders on source change with debouncing, swapping images only once the new one is ready
5. Zoom re-renders at higher resolution for sharp output at every level

## License

MIT
