# inline-rendering Specification

## Purpose
Shows rendered mermaid diagrams directly inside markdown buffers, mermaid (`.mmd`) buffers and AI agent terminals, next to their source, so documents and agent answers read with their diagrams in place without opening a separate viewer.

## Requirements

### Requirement: Render mermaid blocks inline above the fence
In markdown buffers with inline rendering enabled, the system SHALL display the rendered diagram for each ` ```mermaid ` block as virtual lines directly above the block's opening fence. The block's source text SHALL remain unchanged and visible unless the block is collapsed.

#### Scenario: Markdown buffer with mermaid blocks is opened
- **WHEN** a markdown buffer containing two ` ```mermaid ` blocks is displayed in a window
- **THEN** a rendered diagram appears directly above each block's opening fence, and the buffer text is not modified

#### Scenario: Non-mermaid code blocks are ignored
- **WHEN** a markdown buffer contains a ` ```lua ` block
- **THEN** no diagram is rendered for that block

### Requirement: Render mermaid buffers inline below the text
In a buffer with filetype `mermaid` or a `*.mmd` file, with inline rendering enabled, the system SHALL treat the whole buffer as one diagram and display it as virtual lines below the last line. It SHALL NOT be collapsible.

#### Scenario: Opening a .mmd file
- **WHEN** the user opens a non-empty `.mmd` file
- **THEN** its rendered diagram appears below the last line, and edits re-render it like a markdown block

### Requirement: Render diagrams in agent terminals
In a terminal buffer whose filetype is listed in `terminal_filetypes` (default `{ "sidekick_terminal" }`), with inline rendering enabled, the system SHALL display a rendered diagram as virtual lines below each diagram in the terminal output (as found by diagram-rendering), and re-scan the output as it arrives, debounced by `debounce_ms`. A diagram that fails to render SHALL show nothing. Diagrams in terminal output SHALL NOT be collapsible.

#### Scenario: Agent prints a diagram without fences
- **WHEN** an agent in a sidekick terminal prints `  flowchart TD` followed by lines indented by six spaces and then a line indented by two
- **THEN** the rendered flowchart appears below its last indented line

#### Scenario: Prose is not a diagram
- **WHEN** the output contains the line `graph of nodes`
- **THEN** no diagram is detected there

#### Scenario: Diagram still being written
- **WHEN** the agent has printed only part of a diagram and it fails to render
- **THEN** nothing is shown for it until the output renders

### Requirement: Inline diagrams move with the buffer
Inline diagrams SHALL behave like buffer content: they SHALL scroll with the text, stay clipped to the window that shows them, and not appear in windows or screen regions where their block is not displayed.

#### Scenario: Scrolling the buffer
- **WHEN** the user scrolls the window so a diagram's block moves up by ten lines
- **THEN** the diagram moves up with it, and any part scrolled out of the window is not drawn

#### Scenario: Same buffer in two windows
- **WHEN** the buffer is shown in two split windows
- **THEN** each window shows the diagrams for the blocks visible in that window, clipped to that window

### Requirement: Inline diagram size
Each inline diagram SHALL keep its natural size relative to the editor font, multiplied by `inline.scale` (default 1.0), so text has the same size across diagrams. A diagram taller than `inline.max_height` rows or wider than `inline.max_width` SHALL shrink to fit, preserving its aspect ratio, and SHALL never be wider than the window's text area.

#### Scenario: Short and long diagrams
- **WHEN** a small diagram and a long diagram are rendered inline with default settings
- **THEN** the long diagram occupies more rows than the small one and their text is the same size

#### Scenario: Diagram taller than max_height
- **WHEN** a diagram at its natural size would be taller than `inline.max_height` rows
- **THEN** it occupies `inline.max_height` rows and its width shrinks to preserve the aspect ratio

#### Scenario: Very wide diagram in a narrow window
- **WHEN** a diagram at its natural size would be wider than the window's text area
- **THEN** it is scaled to the text area width and its height shrinks proportionally

### Requirement: Inline rendering toggle
Inline rendering SHALL be enabled by default for markdown, mermaid and agent terminal buffers. The user SHALL be able to toggle it per buffer, and to disable it globally through configuration.

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

#### Scenario: A collapsed block takes one move
- **WHEN** the cursor is on the line above a collapsed block and the user presses `j` once
- **THEN** the cursor lands on the first line after the block, in the same column

#### Scenario: Entering insert mode on a collapsed block
- **WHEN** the user enters insert mode with the cursor on a collapsed block's marker
- **THEN** the block's source becomes visible for editing

#### Scenario: Leaving insert mode
- **WHEN** the user returns to normal mode and moves the cursor out of the block
- **THEN** the block is collapsed again

### Requirement: Collapse blocks automatically
When `inline.collapse` is `true` (default `true`), each mermaid block SHALL be collapsed once, when its diagram first renders successfully. A block whose render fails SHALL stay expanded. A block the user expanded SHALL NOT be collapsed again by later renders. A block containing the cursor when it is auto-collapsed SHALL stay visible until the cursor leaves it.

#### Scenario: Opening a markdown file
- **WHEN** `inline.collapse` is `true` and the user opens a markdown file with mermaid blocks
- **THEN** each block shows only its diagram and collapse marker once it has rendered

#### Scenario: Broken diagram
- **WHEN** `inline.collapse` is `true` and a block fails to render
- **THEN** the block stays expanded and shows the error line

#### Scenario: User expands an auto-collapsed block
- **WHEN** the user expands an auto-collapsed block with `:MermaidCollapse` and edits it
- **THEN** the block stays expanded after it re-renders

### Requirement: Double-click opens an inline diagram
When `inline.double_click` is `true` (default `true`), double-clicking an inline diagram or collapse marker SHALL open that diagram in the viewer, closing any viewer already open. A double-click on buffer text SHALL keep Neovim's default behaviour. The mapping SHALL be buffer-local to buffers with inline rendering on, in normal and terminal mode, and SHALL be removed when inline rendering is turned off.

#### Scenario: Double-click on a diagram
- **WHEN** the user double-clicks a row of an inline diagram in a markdown, mermaid or agent terminal buffer
- **THEN** the viewer opens showing that diagram

#### Scenario: Double-click on text
- **WHEN** the user double-clicks buffer text, including a block's own lines
- **THEN** Neovim's default double-click runs and no viewer opens

#### Scenario: Disabled
- **WHEN** `inline.double_click` is `false`
- **THEN** `<2-LeftMouse>` is not mapped
