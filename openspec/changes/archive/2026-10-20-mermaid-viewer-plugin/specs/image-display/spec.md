## ADDED Requirements

### Requirement: Display rendered diagram in a floating window
The system SHALL open a Neovim floating window and display the rendered PNG diagram inside it using image.nvim's Kitty backend.

#### Scenario: First render after triggering viewer
- **WHEN** the diagram renders successfully for the first time
- **THEN** a floating window opens centered in the editor, sized to the configured percentage of the editor dimensions (default 80%), and the PNG is displayed via `image.nvim`'s `from_file` API bound to that window

#### Scenario: Viewer float already open and re-render completes
- **WHEN** a re-render completes while the viewer float is already open
- **THEN** the old image is cleared and the new image is displayed in the same float without closing/reopening the window

### Requirement: Image fits within the floating window
The system SHALL scale the initial image display so the entire diagram is visible within the floating window without clipping.

#### Scenario: Diagram is wider than the float
- **WHEN** the rendered diagram's aspect ratio is wider than the float
- **THEN** the image width matches the float width and the height is scaled proportionally

#### Scenario: Diagram is taller than the float
- **WHEN** the rendered diagram's aspect ratio is taller than the float
- **THEN** the image height matches the float height and the width is scaled proportionally

### Requirement: Double-buffered image swap
The system SHALL use double buffering when updating the displayed image to avoid flicker. The new image MUST be fully loaded before the old image is cleared.

#### Scenario: Re-render on source change
- **WHEN** a re-render produces a new PNG file
- **THEN** the system creates a new image.nvim image from the new file, renders it, and only then clears the previous image

### Requirement: Float window configuration
The floating window SHALL have a configurable border style, size (as percentage of editor dimensions), and position.

#### Scenario: User configures custom float size
- **WHEN** the user sets `float = { width = 0.6, height = 0.6 }` in setup
- **THEN** the float occupies 60% of the editor width and height, centered
