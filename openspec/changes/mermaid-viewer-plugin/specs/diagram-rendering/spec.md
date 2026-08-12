## ADDED Requirements

### Requirement: Extract Mermaid source from .mmd files
The system SHALL treat the entire buffer content of `.mmd` files as Mermaid diagram source.

#### Scenario: Open a .mmd file and render
- **WHEN** the user triggers the viewer on a buffer with filetype `mermaid` or extension `.mmd`
- **THEN** the system extracts the full buffer content as the diagram source

### Requirement: Extract Mermaid source from Markdown code blocks
The system SHALL extract fenced mermaid code blocks (` ```mermaid ... ``` `) from Markdown buffers. When the cursor is inside or adjacent to a mermaid code block, that block is used as the source.

#### Scenario: Cursor inside a mermaid code block
- **WHEN** the user triggers the viewer with the cursor inside a ` ```mermaid ` fenced block
- **THEN** the system extracts the content between the opening and closing fences (excluding the fences themselves) as the diagram source

#### Scenario: No mermaid block at cursor
- **WHEN** the user triggers the viewer in a Markdown buffer with no mermaid code block at the cursor position
- **THEN** the system SHALL display an error notification "No mermaid diagram found at cursor"

### Requirement: Render via mmdr CLI
The system SHALL invoke the `mmdr` binary to render extracted Mermaid source to PNG format. The invocation MUST be asynchronous (non-blocking).

#### Scenario: Successful render
- **WHEN** the system has extracted valid Mermaid source
- **THEN** the system invokes `mmdr -i <temp_input> -o <temp_output> -e png` via `vim.system()` and produces a PNG file

#### Scenario: mmdr returns an error
- **WHEN** `mmdr` exits with a non-zero exit code
- **THEN** the system displays the stderr output as an error notification and does not open or update the viewer

### Requirement: Debounced re-render on source change
The system SHALL re-render the diagram when the source buffer content changes, debounced to avoid excessive renders.

#### Scenario: User edits the source buffer with viewer open
- **WHEN** the viewer is open and the source buffer text changes
- **THEN** the system waits for the configured debounce period (default 300ms) after the last change, then re-renders and updates the displayed image

#### Scenario: Rapid edits within debounce window
- **WHEN** multiple edits occur within the debounce period
- **THEN** only one render is triggered, using the buffer state after the last edit

### Requirement: Temp file cleanup
The system SHALL write rendered PNGs to temporary files and clean them up when the viewer closes or Neovim exits.

#### Scenario: Viewer closes normally
- **WHEN** the user closes the viewer
- **THEN** all temp files (input and output) created for that session are deleted

#### Scenario: Neovim exits with viewer open
- **WHEN** Neovim exits while a viewer is still open
- **THEN** all temp files are deleted via a VimLeavePre autocmd
