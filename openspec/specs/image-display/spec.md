# image-display Specification

## Purpose
Puts rendered diagrams on screen through the Kitty graphics protocol, as buffer content that Neovim scrolls and clips, and manages the image lifecycle in the terminal for the floating viewer.

## Requirements

### Requirement: Display rendered diagram in a floating window
The system SHALL open a Neovim floating window and display the rendered PNG diagram inside it as part of the float's buffer content, using Kitty graphics Unicode placeholders, so the image is drawn only within the float and is clipped by it.

#### Scenario: First render after triggering viewer
- **WHEN** the diagram renders successfully for the first time
- **THEN** a floating window opens centered in the editor, sized to the configured percentage of the editor dimensions (default 80%), and the diagram is displayed inside it

#### Scenario: Viewer float already open and re-render completes
- **WHEN** a re-render completes while the viewer float is already open
- **THEN** the new image replaces the old one in the same float without closing/reopening the window

#### Scenario: Other windows and floats
- **WHEN** another floating window (e.g. a notification) overlaps the viewer
- **THEN** that window is drawn on top of the diagram, and no part of the diagram is drawn outside the viewer float

### Requirement: Image fits within the floating window
The system SHALL scale the initial image display so the entire diagram is visible within the floating window without clipping.

#### Scenario: Diagram is wider than the float
- **WHEN** the rendered diagram's aspect ratio is wider than the float
- **THEN** the image width matches the float width and the height is scaled proportionally

#### Scenario: Diagram is taller than the float
- **WHEN** the rendered diagram's aspect ratio is taller than the float
- **THEN** the image height matches the float height and the width is scaled proportionally

### Requirement: Double-buffered image swap
The system SHALL use double buffering when updating a displayed image to avoid flicker. The new image MUST be fully transmitted to the terminal before the old image is removed. This applies to the viewer and to inline diagrams.

#### Scenario: Re-render on source change
- **WHEN** a re-render produces a new PNG file
- **THEN** the system transmits the new image, switches the display to it, and only then deletes the previous image from the terminal

### Requirement: Float window configuration
The floating window SHALL be centered and sized to the diagram, capped at a configurable percentage of the editor dimensions, with a configurable border style. A user-supplied `float.win_config` table SHALL be merged over the computed window config whenever the window is opened or resized, so any `nvim_open_win` option (title, footer, z-index, position, size, style, border) can be set.

#### Scenario: User configures custom float size
- **WHEN** the user sets `float = { width = 0.6, height = 0.6 }` in setup
- **THEN** the float is centered and never exceeds 60% of the editor width and height

#### Scenario: User passes window options
- **WHEN** the user sets `float = { win_config = { title = " Mermaid ", zindex = 60 } }` and opens the viewer
- **THEN** the float shows the title " Mermaid " and has z-index 60

#### Scenario: Window options survive zoom
- **WHEN** the user has set `float.win_config` with a title and a fixed `row`, and zooms in
- **THEN** the resized float keeps the title and the row

#### Scenario: Fixed window size
- **WHEN** the user sets `float = { win_config = { width = 100, height = 30 } }`
- **THEN** the float is 100 by 30 cells and the diagram at 1.0x zoom fits within it

### Requirement: Reliable delivery to the terminal
Image data SHALL reach the terminal intact regardless of size. Graphics output SHALL be sent through Neovim's UI channel so it is not truncated or interleaved with screen updates.

#### Scenario: Large diagram
- **WHEN** a rendered PNG of several hundred kilobytes is displayed
- **THEN** the terminal receives the complete image and displays it

### Requirement: Viewer state follows the float's lifetime
Closing the viewer float by any means SHALL fully close the viewer: its images are deleted from the terminal, its auto-update stops, and it can be reopened.

#### Scenario: Float closed with :q
- **WHEN** the user closes the viewer float with `:q` or `<C-w>c`
- **THEN** the diagram disappears from the screen and the next `:MermaidView` opens a new viewer

#### Scenario: Inline diagrams restored after zooming
- **WHEN** the user zooms the viewer far enough that the terminal evicts older images, then closes the viewer
- **THEN** every inline diagram is sent to the terminal again under its image id and is shown as before, without re-rendering

### Requirement: Unicode placeholder support required
The system SHALL display images only in terminals that support Kitty graphics Unicode placeholders. In other terminals it SHALL NOT emit graphics data and SHALL inform the user once that diagrams cannot be displayed.

#### Scenario: Unsupported terminal
- **WHEN** the plugin is used in a terminal without Unicode placeholder support
- **THEN** no inline diagrams or viewer images are drawn, and a single warning explains the terminal requirement
