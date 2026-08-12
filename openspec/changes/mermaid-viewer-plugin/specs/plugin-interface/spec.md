## ADDED Requirements

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

### Requirement: Checkhealth integration
The plugin SHALL implement `:checkhealth mermaid-viewer` to validate the runtime environment.

#### Scenario: All dependencies present
- **WHEN** the user runs `:checkhealth mermaid-viewer` with `mmdr` on PATH and `image.nvim` installed
- **THEN** the health check reports OK for both dependencies with their versions

#### Scenario: mmdr missing
- **WHEN** `mmdr` is not found on PATH
- **THEN** the health check reports ERROR with install instructions for mmdr

#### Scenario: image.nvim missing
- **WHEN** `image.nvim` is not loadable
- **THEN** the health check reports ERROR with a link to the image.nvim repository

### Requirement: Close viewer with q or Escape
The viewer float SHALL close when the user presses `q` or `<Esc>` while the float is focused.

#### Scenario: Press q in viewer
- **WHEN** the user presses `q` while the viewer float has focus
- **THEN** the viewer closes (equivalent to `:MermaidClose`)
