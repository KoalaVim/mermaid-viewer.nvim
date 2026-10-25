# plugin-interface Specification

## Purpose
Defines how users drive the plugin: setup options, commands, `<Plug>` mappings and the health check.

## Requirements

### Requirement: setup() function with sensible defaults
The plugin SHALL expose a `require("mermaid-viewer").setup(opts)` function. The plugin MUST work without calling `setup()` — defaults are applied automatically.

#### Scenario: User does not call setup
- **WHEN** the user installs the plugin without calling `setup()`
- **THEN** the plugin works with all default settings when commands are invoked

#### Scenario: User calls setup with partial overrides
- **WHEN** the user calls `setup({ theme = "dark", debounce_ms = 500 })`
- **THEN** those values override the defaults while all other options retain their default values

### Requirement: MermaidView command
The plugin SHALL provide a `:MermaidView` user command that opens the viewer for the current buffer.

#### Scenario: Run MermaidView in a .mmd buffer
- **WHEN** the user runs `:MermaidView` in a buffer containing Mermaid source
- **THEN** the diagram renders and the viewer float opens

#### Scenario: Run MermaidView in an unsupported buffer
- **WHEN** the user runs `:MermaidView` in a buffer with no Mermaid content
- **THEN** the system displays an error notification "No mermaid diagram found"

#### Scenario: Run MermaidView on a collapsed block
- **WHEN** the user runs `:MermaidView` with the cursor on a collapsed block's marker line
- **THEN** the viewer opens for that block

### Requirement: MermaidClose command
The plugin SHALL provide a `:MermaidClose` user command that closes the active viewer.

#### Scenario: Close an open viewer
- **WHEN** the user runs `:MermaidClose` while the viewer is open
- **THEN** the viewer float closes, the image is cleared, and temp files are cleaned up

#### Scenario: Close when no viewer is open
- **WHEN** the user runs `:MermaidClose` with no active viewer
- **THEN** nothing happens (no error)

### Requirement: MermaidToggle command
The plugin SHALL provide a `:MermaidToggle` user command that toggles the viewer open/closed.

#### Scenario: Toggle when viewer is closed
- **WHEN** the user runs `:MermaidToggle` with no active viewer
- **THEN** the viewer opens (equivalent to `:MermaidView`)

#### Scenario: Toggle when viewer is open
- **WHEN** the user runs `:MermaidToggle` with an active viewer
- **THEN** the viewer closes (equivalent to `:MermaidClose`)

### Requirement: Plug keymaps
The plugin SHALL expose `<Plug>` mappings for all actions so users can bind them to their preferred keys.

#### Scenario: User maps a Plug keymap
- **WHEN** the user adds `vim.keymap.set("n", "<leader>mv", "<Plug>(mermaid-viewer-toggle)")` to their config
- **THEN** pressing `<leader>mv` toggles the viewer

#### Scenario: Inline and collapse mappings
- **WHEN** the user maps `<Plug>(mermaid-viewer-inline-toggle)` and `<Plug>(mermaid-viewer-collapse-toggle)`
- **THEN** those keys toggle inline rendering for the buffer and collapse the block under the cursor, respectively

### Requirement: Checkhealth integration
The plugin SHALL implement `:checkhealth mermaid-viewer` to validate the runtime environment.

#### Scenario: All dependencies present
- **WHEN** the user runs `:checkhealth mermaid-viewer` with `mmdr` on PATH, Neovim 0.12 or newer, and a terminal with Unicode placeholder support
- **THEN** the health check reports OK for each, including the `mmdr` version and the detected terminal

#### Scenario: mmdr missing
- **WHEN** `mmdr` is not found on PATH
- **THEN** the health check reports ERROR with install instructions for mmdr

#### Scenario: image.nvim missing
- **WHEN** `image.nvim` is not installed
- **THEN** the health check does not report it, since it is not a dependency

#### Scenario: Terminal without placeholder support
- **WHEN** the detected terminal does not support Kitty graphics Unicode placeholders
- **THEN** the health check reports ERROR naming the supported terminals

### Requirement: Close viewer with q or Escape
The viewer float SHALL close when the user presses `q` or `<Esc>` while the float is focused.

#### Scenario: Press q in viewer
- **WHEN** the user presses `q` while the viewer float has focus
- **THEN** the viewer closes (equivalent to `:MermaidClose`)

### Requirement: MermaidInline command
The plugin SHALL provide a `:MermaidInline` user command that toggles inline rendering for the current buffer.

#### Scenario: Run MermaidInline in a markdown buffer
- **WHEN** the user runs `:MermaidInline` in a markdown buffer
- **THEN** inline rendering for that buffer switches between on and off

#### Scenario: Run MermaidInline in an unsupported buffer
- **WHEN** the user runs `:MermaidInline` in a buffer that is not markdown, mermaid or an agent terminal
- **THEN** the system displays a notification that inline rendering applies to markdown, mermaid and agent terminal buffers only

### Requirement: MermaidCollapse command
The plugin SHALL provide a `:MermaidCollapse` user command that toggles collapse for the mermaid block under the cursor.

#### Scenario: Collapse from the command
- **WHEN** the user runs `:MermaidCollapse` with the cursor inside an expanded mermaid block
- **THEN** that block collapses

#### Scenario: No block under the cursor
- **WHEN** the user runs `:MermaidCollapse` with no mermaid block under the cursor
- **THEN** nothing changes and the system displays "No mermaid diagram found at cursor"

### Requirement: Inline configuration options
`setup()` SHALL accept an `inline` table with `enabled` (default `true`), `collapse` (default `true`), `scale` (default `1.0`), `max_width` (default `1.0`) and `max_height` (default `40`); for both limits a value <= 1 is a fraction of the window and a value > 1 is cells, applied to buffers opened after setup. The removed `inline.height` option SHALL be ignored with a warning.

#### Scenario: Custom inline max height
- **WHEN** the user calls `setup({ inline = { max_height = 10 } })`
- **THEN** inline diagrams occupy at most 10 rows

#### Scenario: Removed height option
- **WHEN** the user calls `setup({ inline = { height = 20 } })`
- **THEN** a warning names `inline.scale`, `inline.max_height` and `inline.max_width`, and the option is ignored
