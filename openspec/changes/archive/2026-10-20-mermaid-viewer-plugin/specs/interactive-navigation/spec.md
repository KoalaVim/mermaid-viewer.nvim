## ADDED Requirements

### Requirement: Zoom in
The system SHALL support zooming in on the diagram, increasing the visible detail by re-rendering at a higher resolution and displaying a cropped region within the floating window.

#### Scenario: User zooms in from fit-to-window view
- **WHEN** the user presses the zoom-in key (default `+` or `=`)
- **THEN** the zoom level increases by one step (e.g., 1.0x → 1.5x), the diagram re-renders at the higher resolution, and the view centers on the same region

#### Scenario: Zoom in at maximum level
- **WHEN** the user presses zoom-in at the maximum zoom level (default 5.0x)
- **THEN** nothing happens (the zoom level does not exceed the maximum)

### Requirement: Zoom out
The system SHALL support zooming out to see more of the diagram.

#### Scenario: User zooms out from zoomed-in view
- **WHEN** the user presses the zoom-out key (default `-`)
- **THEN** the zoom level decreases by one step (e.g., 2.0x → 1.5x) and the view updates

#### Scenario: Zoom out at minimum level
- **WHEN** the user presses zoom-out at the minimum zoom level (1.0x, fit-to-window)
- **THEN** nothing happens (the zoom level does not go below 1.0x)

### Requirement: Reset zoom
The system SHALL support resetting the zoom level back to fit-to-window (1.0x).

#### Scenario: User resets zoom
- **WHEN** the user presses the reset key (default `0`)
- **THEN** the zoom level returns to 1.0x and the entire diagram fits within the float

### Requirement: Pan in four directions
The system SHALL support panning the viewport in four directions (up, down, left, right) when the diagram is zoomed in beyond the float boundaries.

#### Scenario: Pan right while zoomed in
- **WHEN** the user presses the pan-right key (default `l` or right arrow) while zoomed in
- **THEN** the viewport shifts right, revealing more of the diagram to the right

#### Scenario: Pan at diagram edge
- **WHEN** the user pans in a direction where no more diagram content exists
- **THEN** the viewport stops at the edge and does not scroll further

#### Scenario: Pan while at fit-to-window zoom
- **WHEN** the user presses a pan key while at 1.0x zoom (entire diagram visible)
- **THEN** nothing happens (there is nothing to pan to)

### Requirement: Configurable navigation keymaps
The system SHALL allow users to override the default zoom and pan keybindings via the `setup()` configuration.

#### Scenario: User sets custom keybindings
- **WHEN** the user configures `keys = { zoom_in = "<C-=>", zoom_out = "<C-->" }` in setup
- **THEN** the viewer uses `<C-=>` and `<C-->` instead of the defaults
