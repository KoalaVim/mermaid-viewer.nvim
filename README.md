# mermaid-viewer.nvim

View Mermaid diagrams inside Neovim with interactive zoom and pan. Renders diagrams using [mmdr](https://github.com/mermaid-rs/mermaid-rs) and displays them via the [Kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/).

## Requirements

- Neovim >= 0.10.0
- [mmdr](https://github.com/mermaid-rs/mermaid-rs) - Fast Mermaid renderer written in Rust
- A terminal that supports the Kitty graphics protocol ([Kitty](https://sw.kovidgoyal.net/kitty/), [WezTerm](https://wezfurlong.org/wezterm/), [Ghostty](https://ghostty.org/))

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
  cmd = { "MermaidView", "MermaidClose", "MermaidToggle" },
  ft = { "markdown", "mermaid" },
  keys = {
    { "<leader>um", "<cmd>MermaidToggle<cr>", ft = { "markdown", "mermaid" }, desc = "Mermaid Viewer" },
  },
  opts = {},
}
```

## Usage

Open a `.mmd` file or place your cursor inside a `mermaid` code block in a Markdown file, then:

| Command | Description |
|---|---|
| `:MermaidView` | Open the viewer |
| `:MermaidClose` | Close the viewer |
| `:MermaidToggle` | Toggle the viewer |

### Viewer keymaps

| Key | Action |
|---|---|
| `+` / `=` | Zoom in |
| `-` | Zoom out |
| `0` | Reset zoom (fit to window) |
| `h` `j` `k` `l` | Pan left / down / up / right |
| `q` / `<Esc>` | Close viewer |

### Plug mappings

```lua
vim.keymap.set("n", "<leader>um", "<Plug>(mermaid-viewer-toggle)")
vim.keymap.set("n", "<leader>uM", "<Plug>(mermaid-viewer-view)")
```

## Configuration

The plugin works out of the box with no configuration. Call `setup()` only to override defaults:

```lua
require("mermaid-viewer").setup({
  mmdr_path = "mmdr",       -- path to mmdr binary
  theme = "default",        -- mermaid theme: "default", "dark", "forest", "neutral", "modern"
  debounce_ms = 300,        -- debounce delay for auto-update on source change
  fast_text = false,        -- use mmdr --fastText for faster rendering
  auto_update = true,       -- re-render when source buffer changes

  float = {
    width = 0.8,            -- float width as percentage of editor (0.0-1.0)
    height = 0.8,           -- float height as percentage of editor (0.0-1.0)
    border = "rounded",     -- border style
  },

  keys = {
    zoom_in = "+",
    zoom_out = "-",
    zoom_reset = "0",
    pan_up = "k",
    pan_down = "j",
    pan_left = "h",
    pan_right = "l",
    close = { "q", "<Esc>" },
  },

  zoom_step = 1.5,          -- zoom multiplier per step
  max_zoom = 5.0,           -- maximum zoom level
  pan_step = 5,             -- cells to shift per pan action
})
```

## Health check

Run `:checkhealth mermaid-viewer` to verify your setup.

## How it works

1. Extracts Mermaid source from the current buffer (full buffer for `.mmd` files, fenced code block at cursor for Markdown)
2. Renders to PNG via `mmdr` asynchronously
3. Displays the image in a floating window using the Kitty graphics protocol directly (no ImageMagick or image.nvim required)
4. Re-renders on source change with debouncing
5. Zoom re-renders at higher resolution for sharp output at every level

## License

MIT
