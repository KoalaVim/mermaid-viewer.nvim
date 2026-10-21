## MODIFIED Requirements

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

### Requirement: Double-buffered image swap
The system SHALL use double buffering when updating a displayed image to avoid flicker. The new image MUST be fully transmitted to the terminal before the old image is removed. This applies to the viewer and to inline diagrams.

#### Scenario: Re-render on source change
- **WHEN** a re-render produces a new PNG file
- **THEN** the system transmits the new image, switches the display to it, and only then deletes the previous image from the terminal

## ADDED Requirements

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

### Requirement: Unicode placeholder support required
The system SHALL display images only in terminals that support Kitty graphics Unicode placeholders. In other terminals it SHALL NOT emit graphics data and SHALL inform the user once that diagrams cannot be displayed.

#### Scenario: Unsupported terminal
- **WHEN** the plugin is used in a terminal without Unicode placeholder support
- **THEN** no inline diagrams or viewer images are drawn, and a single warning explains the terminal requirement
