# diagram-rendering Specification

## Purpose
Finds Mermaid source in `.mmd` files, markdown fenced blocks and AI agent terminal output, and turns it into PNG images with `mmdr`, keeping renders in step with edits and cached so unchanged diagrams are never rendered twice.

## Requirements

### Requirement: Extract Mermaid source from .mmd files
The system SHALL treat the entire buffer content of `.mmd` files as Mermaid diagram source.

#### Scenario: Open a .mmd file and render
- **WHEN** the user triggers the viewer on a buffer with filetype `mermaid` or extension `.mmd`
- **THEN** the system extracts the full buffer content as the diagram source

### Requirement: Extract Mermaid source from Markdown code blocks
The system SHALL extract fenced mermaid code blocks (` ```mermaid ... ``` `) from Markdown buffers. When the cursor is inside a mermaid code block, on its fences, on its inline diagram or collapse marker, or on the line just above the block, that block is used as the source. Once a viewer is opened for a block, the viewer SHALL stay bound to that block regardless of which window has focus or where the cursor moves.

#### Scenario: Cursor inside a mermaid code block
- **WHEN** the user triggers the viewer with the cursor inside a ` ```mermaid ` fenced block
- **THEN** the system extracts the content between the opening and closing fences (excluding the fences themselves) as the diagram source

#### Scenario: Cursor on the line above a block
- **WHEN** the user triggers the viewer with the cursor on the line just above a ` ```mermaid ` block (expanded or collapsed)
- **THEN** that block is used as the source

#### Scenario: No mermaid block at cursor
- **WHEN** the user triggers the viewer in a Markdown buffer with no mermaid code block at the cursor position
- **THEN** the system SHALL display an error notification "No mermaid diagram found at cursor"

#### Scenario: Viewer keeps its block after focus moves to the float
- **WHEN** the viewer is open for a block and focus is inside the viewer float
- **THEN** zooming shows and auto-update re-renders that same block's source

#### Scenario: Lines are inserted above the bound block
- **WHEN** the viewer is open and the user inserts lines above the block in the source buffer
- **THEN** the viewer still renders the same block

### Requirement: Extract Mermaid source from agent terminal output
The system SHALL find diagrams in terminal buffers whose filetype is listed in `terminal_filetypes` (default `{ "sidekick_terminal" }`): closed ` ```mermaid ` fences at any indent, and unfenced diagrams made of a mermaid declaration line followed by more-indented lines. The common indent of the declaration SHALL be removed from the source. The viewer SHALL use the diagram under the cursor.

#### Scenario: Unfenced diagram boundaries
- **WHEN** the output has a declaration line (`flowchart TD`, `graph LR`, `sequenceDiagram`, ...) followed by lines indented more than it
- **THEN** the diagram spans the declaration and those lines, including blank lines between them, and ends before the next non-blank line indented no more than the declaration; a declaration without such lines is not a diagram

#### Scenario: Long agent session
- **WHEN** the terminal holds thousands of lines of output and a window shows its end
- **THEN** only diagrams starting near the window (a screen above and below, plus 100 rows above) are scanned for, so the cost does not grow with the scrollback; a diagram starting there is followed to its end

#### Scenario: Viewer on agent output
- **WHEN** the user triggers the viewer with the cursor on a line of an unfenced `sequenceDiagram` in a sidekick terminal
- **THEN** the system extracts the declaration and its indented lines, dedented, as the diagram source

### Requirement: Render via mmdr CLI
The system SHALL invoke the `mmdr` binary to render extracted Mermaid source to PNG format. The invocation MUST be asynchronous (non-blocking). The requested pixel size SHALL be derived from the target size in terminal cells and the terminal's cell size in pixels, and SHALL NOT exceed 10000 pixels on either side or 2048×2048 pixels of area. The configured theme SHALL be passed to every render.

#### Scenario: Successful render
- **WHEN** the system has extracted valid Mermaid source
- **THEN** the system invokes `mmdr -i <temp_input> -o <temp_output> -e png` via `vim.system()` and produces a PNG file

#### Scenario: mmdr returns an error
- **WHEN** `mmdr` exits with a non-zero exit code
- **THEN** the system reports the stderr output (as an error notification for the viewer, or as an inline error indicator for inline diagrams) and does not replace the currently displayed image

#### Scenario: Large target area
- **WHEN** the target area at the current zoom would exceed 10000 pixels on a side
- **THEN** the requested size is scaled down proportionally so the larger side is 10000 pixels

#### Scenario: Deep zoom stays within the area cap
- **WHEN** the target area at the current zoom would exceed 2048×2048 pixels
- **THEN** the requested size is scaled down proportionally to that area, and the terminal still displays the image

#### Scenario: Configured theme
- **WHEN** the user configures `theme = "dark"`
- **THEN** both inline and viewer renders use the dark theme

### Requirement: Debounced re-render on source change
The system SHALL re-render diagrams when their source changes, debounced to avoid excessive renders. This applies to the open viewer and to inline diagrams.

#### Scenario: User edits the source buffer with viewer open
- **WHEN** the viewer is open and the source of its block changes
- **THEN** the system waits for the configured debounce period (default 300ms) after the last change, then re-renders and updates the displayed image

#### Scenario: Rapid edits within debounce window
- **WHEN** multiple edits occur within the debounce period
- **THEN** only one render is triggered per affected block, using the buffer state after the last edit

### Requirement: Temp file cleanup
The system SHALL keep rendered PNGs in a cache keyed by diagram source, render size and theme, so identical diagrams are not re-rendered. Cached files SHALL be stored under a plugin-owned temporary directory and removed when Neovim exits.

#### Scenario: Same diagram shown again
- **WHEN** a diagram with unchanged source, size and theme needs to be displayed again (e.g. after toggling inline rendering or reopening the viewer)
- **THEN** the cached PNG is reused and `mmdr` is not invoked

#### Scenario: Viewer closes normally
- **WHEN** the user closes the viewer
- **THEN** temporary input files created for that viewer are deleted, while cached PNGs are kept for reuse until Neovim exits

#### Scenario: Neovim exits with viewer open
- **WHEN** Neovim exits, with or without a viewer open
- **THEN** all temporary input files and cached PNGs created by the plugin are deleted via a VimLeavePre autocmd
