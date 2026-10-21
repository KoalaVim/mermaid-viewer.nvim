# Spec Delta

## Purpose

Shows rendered mermaid diagrams directly inside markdown buffers, next to their source blocks, so documents read with their diagrams in place without opening a separate viewer.

## ADDED Requirements

### Requirement: Render mermaid blocks inline above the fence
In markdown buffers with inline rendering enabled, the system SHALL display the rendered diagram for each ` ```mermaid ` block as virtual lines directly above the block's opening fence. The block's source text SHALL remain unchanged and visible unless the block is collapsed.

#### Scenario: Markdown buffer with mermaid blocks is opened
- **WHEN** a markdown buffer containing two ` ```mermaid ` blocks is displayed in a window
- **THEN** a rendered diagram appears directly above each block's opening fence, and the buffer text is not modified

#### Scenario: Non-mermaid code blocks are ignored
- **WHEN** a markdown buffer contains a ` ```lua ` block
- **THEN** no diagram is rendered for that block

### Requirement: Inline diagrams move with the buffer
Inline diagrams SHALL behave like buffer content: they SHALL scroll with the text, stay clipped to the window that shows them, and not appear in windows or screen regions where their block is not displayed.

#### Scenario: Scrolling the buffer
- **WHEN** the user scrolls the window so a diagram's block moves up by ten lines
- **THEN** the diagram moves up with it, and any part scrolled out of the window is not drawn

#### Scenario: Same buffer in two windows
- **WHEN** the buffer is shown in two split windows
- **THEN** each window shows the diagrams for the blocks visible in that window, clipped to that window

### Requirement: Inline diagram size
Each inline diagram SHALL be scaled to a configurable height in rows (default 15), with width following the diagram's aspect ratio. When that width would exceed the window's text area, the diagram SHALL be scaled down to fit the width, reducing its height proportionally.

#### Scenario: Tall diagram
- **WHEN** a diagram whose natural aspect ratio is taller than wide is rendered inline with the default height
- **THEN** it occupies 15 rows and its width in columns preserves the aspect ratio

#### Scenario: Very wide diagram in a narrow window
- **WHEN** a diagram scaled to 15 rows would be wider than the window's text area
- **THEN** it is scaled to the text area width and occupies fewer than 15 rows, preserving the aspect ratio

### Requirement: Inline rendering toggle
Inline rendering SHALL be enabled by default for markdown buffers. The user SHALL be able to toggle it per buffer, and to disable it globally through configuration.

#### Scenario: Toggle off in one buffer
- **WHEN** the user runs `:MermaidInline` in a markdown buffer showing inline diagrams
- **THEN** all inline diagrams and collapse markers in that buffer are removed, collapsed blocks become visible, and other buffers are unaffected

#### Scenario: Toggle back on
- **WHEN** the user runs `:MermaidInline` again in that buffer
- **THEN** inline diagrams are shown again for all its mermaid blocks

#### Scenario: Globally disabled
- **WHEN** the user configures `inline = { enabled = false }`
- **THEN** markdown buffers open without inline diagrams, and `:MermaidInline` enables them for the current buffer

### Requirement: Inline diagrams follow source edits
When the source of a mermaid block changes, its inline diagram SHALL re-render after the configured debounce period. The previous diagram SHALL remain displayed until the new one is ready. Blocks whose source did not change SHALL NOT be re-rendered.

#### Scenario: Editing a block
- **WHEN** the user edits the text inside one mermaid block and stops typing
- **THEN** after the debounce period that block's diagram is replaced by the updated rendering, without a blank gap, and other blocks' diagrams are unchanged

#### Scenario: Adding a new block
- **WHEN** the user finishes typing a new ` ```mermaid ` block with a closing fence
- **THEN** a diagram appears above it after the debounce period

### Requirement: Inline render errors
When a block's source fails to render, the system SHALL show a short single-line error indicator above the block instead of a diagram, and SHALL NOT raise an error notification for every keystroke while the block is being edited.

#### Scenario: Invalid mermaid syntax
- **WHEN** a block contains invalid mermaid syntax
- **THEN** a one-line indicator containing the renderer's error message appears above the block's fence

#### Scenario: Error is fixed
- **WHEN** the user corrects the syntax
- **THEN** the indicator is replaced by the rendered diagram

### Requirement: Collapse a mermaid block
The user SHALL be able to collapse a mermaid block so its source lines (including fences) are hidden and replaced by a single marker line `··· N lines (mermaid)` below the inline diagram, and to expand it again with the same toggle.

#### Scenario: Collapse a block
- **WHEN** the user triggers the collapse toggle with the cursor on a mermaid block, its inline diagram, or its marker
- **THEN** the block's source lines are hidden and a marker showing the hidden line count appears below the diagram

#### Scenario: Expand a block
- **WHEN** the user triggers the collapse toggle on a collapsed block
- **THEN** the source lines become visible again and the marker is removed

### Requirement: Collapsed blocks expand only for editing
A collapsed block SHALL stay collapsed while the user moves through it in normal mode. Entering insert or visual mode with the cursor on a collapsed block SHALL expand it; leaving that mode with the cursor outside the block SHALL collapse it again.

#### Scenario: Moving over a collapsed block in normal mode
- **WHEN** the user moves the cursor with `j`/`k` across a collapsed block
- **THEN** the block stays collapsed

#### Scenario: Entering insert mode on a collapsed block
- **WHEN** the user enters insert mode with the cursor on a collapsed block's marker
- **THEN** the block's source becomes visible for editing

#### Scenario: Leaving insert mode
- **WHEN** the user returns to normal mode and moves the cursor out of the block
- **THEN** the block is collapsed again
