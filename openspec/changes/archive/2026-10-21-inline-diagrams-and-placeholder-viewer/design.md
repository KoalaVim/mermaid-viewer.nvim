## Context

See proposal.md for motivation. Current state of the code:

- `kitty.lua` transmits PNGs (`a=t`, now via `nvim_ui_send` in one write) and places them at screen coordinates (`ESC[row;colH` + `a=p`, `z=-1`). Placement is outside Neovim's redraw model, so it can't scroll, clip, or survive redraws.
- `source.lua` reads the cursor of window `0`, which is the float once the viewer is open; zoom and auto-update in markdown fail because of it.
- `state.lua` is cleared only by `close()`; closing the float with `:q` leaves stale state.
- Render size comes from `kitty.pixel_size()` (real cell pixels via `TIOCGWINSZ`, capped at 10000px).
- `mmdr` given both `--width` and `--height` fits the diagram inside that box and pads the rest, so the PNG aspect is the box's, not the diagram's.

Constraints: Neovim 0.12 (`nvim_ui_send`), Ghostty/Kitty as primary terminals, herdr as a daily multiplexer, render-markdown.nvim active in the same buffers.

## Goals / Non-Goals

**Goals:**
- One display mechanism for inline and float.
- Inline rendering cheap enough to leave on: no re-render on scroll, only on source change.
- Images never drawn outside the window that owns them.

**Non-Goals:**
- Fallback rendering for terminals without placeholder support (WezTerm, sixel).
- Mouse-driven zoom.
- Rendering mermaid outside markdown/`.mmd` (e.g. mermaid in code comments).
- Inline rendering in `.mmd` buffers (the whole buffer is the source; the float covers it).

## Decisions

### 1. Kitty Unicode placeholders for all display

Transmit each PNG once, create a **virtual placement** (`a=p,U=1,i=<id>,c=<cols>,r=<rows>`), and draw it by putting placeholder cells (U+10EEEE followed by row/column diacritics) into buffer content. The image id is encoded in the cell's foreground color, so each image gets a highlight group with `fg = <id>` (24-bit, requires `termguicolors`).

Inline: one extmark per block with `virt_lines` (`virt_lines_above = true`) on the opening fence, each virtual line being one row of placeholder cells. Float: the same rows as real lines in a scratch buffer.

Why: images become text, so scrolling, folding, splits, window clipping, overlapping floats and `<C-l>` all work with no extra code, and there is no cursor save/restore or z-index handling.

Alternatives:
- *Screen-coordinate placements (current)*: would need repositioning on every `WinScrolled`/redraw, manual clipping against windows and floats, and still flickers. Rejected.
- *snacks.image*: already implements placeholders and inline docs, but its mermaid converter is hardcoded to `mmdc`, its float has no zoom, and it adds a dependency KoalaVim doesn't otherwise enable. Use its `placement.lua` (`render_grid`) as reference only.

### 2. Image ids and lifetime

Kitty image ids are global to the terminal, shared with other plugins. Allocate ids from a random 24-bit base per Neovim instance and increment from there. A registry maps `cache key → { id, cols, rows, refcount }`. An image is deleted from the terminal (`a=d,d=I`) when its refcount drops to zero: block removed, source changed (after the replacement is displayed — double buffering), inline toggled off, buffer wiped, or viewer closed.

### 3. Sizing: learn the aspect ratio, then render to fit

Because `mmdr` pads to the requested box, first render at natural size (no size flags) and read the PNG's IHDR width/height. Cache that aspect per source hash. Then:

- Inline: `rows = inline.height`, `cols = round(rows * cell_h * aspect / cell_w)`; if `cols > text width`, set `cols = text width` and shrink `rows`. Request `cols*cell_w × rows*cell_h` px (aspect matches, so no padding).
- Float at zoom z: fit the float's cells at 1.0x, multiply by z, cap each side at 297 cells and 10000 px.

The natural render can be the displayed one when its size is already close to the target (avoids a second `mmdr` call for small diagrams).

### 4. Block tracking

Treesitter (markdown parser) finds ` ```mermaid ` fenced blocks; line scan stays as fallback. Each block is anchored by an extmark on its opening fence so it keeps its identity across edits above it. On `TextChanged`/`TextChangedI` (debounced), rescan: blocks whose source hash changed are re-rendered; new blocks get anchors; vanished blocks release their images.

The viewer stores the block's anchor extmark (or "whole buffer" for `.mmd`) instead of reading any window's cursor, which fixes zoom/auto-update.

### 5. Render only what is visible

Render blocks whose fence is within the visible range of any window showing the buffer (plus a margin of one screen), triggered on `BufWinEnter`, `WinScrolled`, and rescans. Off-screen blocks render when scrolled into view; cached results are reused.

### 6. Collapse mechanism

Preferred: extmark `conceal_lines` over the block's lines (fences included) plus a virtual line `··· N lines (mermaid)` after the diagram. Normal-mode cursor movement must not reveal concealed lines; whether that holds depends on `concealcursor` and render-markdown's own conceal handling, so it is verified first (task 1.2). Expansion is driven by `ModeChanged` (entering insert/visual with the cursor on the block) and re-collapse by `ModeChanged` back to normal plus `CursorMoved` out of the block.

Fallback if the spike fails: manual closed folds with a custom `foldtext`. Rejected as the default because manual folds conflict with `foldmethod=expr`/treesitter folding the user may already use in markdown.

Collapsed state is per block, held on the anchor extmark, and not persisted across sessions.

### 7. Float as a placeholder buffer

The float buffer holds the placeholder rows as real lines, `nowrap`, `modifiable=false`, no number/sign columns, `scrolloff=0`, `sidescrolloff=0`. Native motions, `<C-d>`, `zh/zl` and the mouse wheel move the view; Neovim clips at buffer edges. Zoom rebuilds the lines for the new grid and restores the view so the previously centered cell stays centered (`winsaveview`/`winrestview` scaled by the zoom ratio). At 1.0x the grid fits in the float, so there is nothing to scroll.

A `WinClosed` autocmd on the float runs the full close path, so `:q`/`<C-w>c` clean up like `q`.

### 8. Terminal output and detection

All graphics go through `nvim_ui_send` in one call per operation (transmit + virtual placement together). Responses stay off (`q=2`) in normal operation; a `debug` config option turns them on and logs `TermResponse` replies, which is how delivery problems were diagnosed.

Placeholder support is detected from `TERM_PROGRAM`/`TERM` (kitty, ghostty, and herdr if task 1.1 confirms), with a config override. Unsupported terminals get one warning and no graphics output.

### 9. Spikes deferred to integration

Spikes 1.1–1.3 need visual confirmation in a real terminal and were not run before implementation. Implementation proceeds on the defaults above — placeholders work in Ghostty and herdr (herdr provisionally marked supported), `conceal_lines` for collapse, `virt_lines_above` on the opening fence — and each assumption is checked during the group 10 integration walkthrough. A failed check routes back to the fallback named in the matching decision.

Result (2026-10-21 walkthrough in Ghostty and herdr): all three defaults hold. Placeholders display, scroll and clip in both terminals, so herdr stays marked supported. `conceal_lines` keeps collapsed blocks hidden in normal mode, given that the plugin adds `n` to `concealcursor`. Diagram lines above the fence coexist with render-markdown's code block styling. No fallback was needed.

## Risks / Trade-offs

- [herdr may not support virtual placements fully] → Task 1.1 tests it in herdr first; if it fails, herdr is listed as unsupported and the config override allows forcing it on.
- [`conceal_lines` reveals lines under the cursor in normal mode] → Task 1.2 spike; fall back to folds (decision 6).
- [render-markdown restyles fences and may draw over our virtual lines] → Task 1.3 checks that both extmarks coexist on the fence line; if not, attach our virtual lines to the line before the fence.
- [`termguicolors` off] → Image ids can't be encoded in colors; health check reports it, and inline rendering stays off.
- [Many diagrams in one document] → Visible-only rendering plus caching; transmitted images held in the terminal are freed by refcount.
- [297-cell placeholder limit] → Zoom cap (spec); inline height defaults are far below it.
- [Two-step render doubles `mmdr` calls on first view] → `mmdr` takes ~50–100ms; natural-size result is reused for small diagrams and cached by hash.

## Migration Plan

- Breaking config: remove `pan_step` and `keys.pan_*`; unknown keys are ignored with a one-time warning naming the replacement (native motions).
- KoalaVim: keep `<leader>um` for the viewer; add `<leader>ui` (`:MermaidInline`) and `<leader>uc` (`:MermaidCollapse`) for markdown buffers in the plugin spec in `lua/KoalaVim/plugins/lsp/servers/markdown.lua`.
- Rollback: KoalaVim's lockfile pins the plugin commit; reverting the pin restores the current viewer.

## Open Questions

- Whether the inline error indicator should also show the failing line number when `mmdr` reports one.
