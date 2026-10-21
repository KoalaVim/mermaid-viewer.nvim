## MODIFIED Requirements

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

## ADDED Requirements

### Requirement: MermaidInline command
The plugin SHALL provide a `:MermaidInline` user command that toggles inline rendering for the current buffer.

#### Scenario: Run MermaidInline in a markdown buffer
- **WHEN** the user runs `:MermaidInline` in a markdown buffer
- **THEN** inline rendering for that buffer switches between on and off

#### Scenario: Run MermaidInline outside markdown
- **WHEN** the user runs `:MermaidInline` in a buffer that is not markdown
- **THEN** the system displays a notification that inline rendering applies to markdown buffers only

### Requirement: MermaidCollapse command
The plugin SHALL provide a `:MermaidCollapse` user command that toggles collapse for the mermaid block under the cursor.

#### Scenario: Collapse from the command
- **WHEN** the user runs `:MermaidCollapse` with the cursor inside an expanded mermaid block
- **THEN** that block collapses

#### Scenario: No block under the cursor
- **WHEN** the user runs `:MermaidCollapse` with no mermaid block under the cursor
- **THEN** nothing changes and the system displays "No mermaid diagram found at cursor"

### Requirement: Inline configuration options
`setup()` SHALL accept an `inline` table with `enabled` (default `true`) and `height` in rows (default `15`), applied to buffers opened after setup.

#### Scenario: Custom inline height
- **WHEN** the user calls `setup({ inline = { height = 10 } })`
- **THEN** inline diagrams are scaled to at most 10 rows
