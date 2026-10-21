## MODIFIED Requirements

### Requirement: Zoom in
The system SHALL support zooming in on the diagram, increasing the visible detail by re-rendering at a higher resolution and enlarging the displayed diagram within the floating window. The zoom level SHALL NOT exceed the configured maximum, nor the size at which the diagram would exceed 297 cells on either side.

#### Scenario: User zooms in from fit-to-window view
- **WHEN** the user presses the zoom-in key (default `+` or `=`)
- **THEN** the zoom level increases by one step (e.g., 1.0x → 1.5x), the diagram re-renders at the higher resolution, and the view centers on the same region

#### Scenario: Zoom in at maximum level
- **WHEN** the user presses zoom-in at the maximum zoom level (default 5.0x)
- **THEN** nothing happens (the zoom level does not exceed the maximum)

#### Scenario: Zoom limited by diagram size in cells
- **WHEN** one more zoom step would make the diagram wider or taller than 297 cells
- **THEN** the zoom level is capped at the largest level that fits within 297 cells

### Requirement: Configurable navigation keymaps
The system SHALL allow users to override the default zoom and close keybindings via the `setup()` configuration. Movement inside the viewer uses Neovim's own motions and is not remapped.

#### Scenario: User sets custom keybindings
- **WHEN** the user configures `keys = { zoom_in = "<C-=>", zoom_out = "<C-->" }` in setup
- **THEN** the viewer uses `<C-=>` and `<C-->` instead of the defaults

## ADDED Requirements

### Requirement: Move around with native motions
When the diagram is larger than the viewer float, the user SHALL be able to move around it with Neovim's normal scrolling and cursor motions, and the view SHALL stop at the diagram's edges.

#### Scenario: Scroll horizontally while zoomed in
- **WHEN** the diagram is wider than the float and the user presses `l`, `zl` or `zL`, or scrolls the mouse wheel horizontally
- **THEN** the view moves right, revealing more of the diagram to the right

#### Scenario: Scroll vertically while zoomed in
- **WHEN** the diagram is taller than the float and the user presses `j`, `<C-d>`, or scrolls the mouse wheel
- **THEN** the view moves down, revealing more of the diagram below

#### Scenario: At fit-to-window zoom
- **WHEN** the whole diagram fits in the float and the user presses a motion key
- **THEN** the view does not move away from the diagram

## REMOVED Requirements

### Requirement: Pan in four directions
**Reason**: Replaced by "Move around with native motions"; the diagram is buffer content in the viewer, so standard motions and the mouse wheel move the view.
**Migration**: Remove `keys.pan_up`, `keys.pan_down`, `keys.pan_left`, `keys.pan_right` and `pan_step` from `setup()`. `h`/`j`/`k`/`l` keep working as native motions.
