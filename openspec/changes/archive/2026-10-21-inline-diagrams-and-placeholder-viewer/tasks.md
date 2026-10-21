# Tasks

## 1. Spikes (decide before building on them)

- [x] 1.1 Placeholder spike: transmit a PNG, create a virtual placement (`U=1`) and write placeholder rows into a scratch buffer via `nvim_ui_send`; verify the image shows and scrolls with the text in plain Ghostty and in herdr (record herdr result in design.md decision 8)
- [x] 1.2 Collapse spike: hide a block with extmark `conceal_lines` in a markdown buffer with render-markdown active; verify `j`/`k` across it in normal mode keeps it hidden and entering insert reveals it — if not, prototype closed manual folds and record the chosen mechanism in design.md decision 6
- [x] 1.3 render-markdown coexistence spike: attach `virt_lines_above` to a ` ```mermaid ` fence line rendered by render-markdown; verify both the placeholder rows and render-markdown's code block styling display correctly (record result under Risks in design.md)

## 2. Terminal graphics layer

- [x] 2.1 Add virtual placement + placeholder row generation (diacritics table, per-image highlight `fg = id`) to `kitty.lua`; verify with a busted test that a 3×2 grid produces the expected placeholder strings and highlight color
- [x] 2.2 Add image registry (random 24-bit id base, cache key → id/cols/rows/refcount, delete on refcount 0); verify with busted tests for acquire/release/delete ordering
- [x] 2.3 Add terminal support detection (kitty, ghostty, herdr per 1.1, config override) and `termguicolors` check, with a single warning when unsupported; verify by running with `TERM_PROGRAM=WezTerm` that no graphics are sent and one warning appears
- [x] 2.4 Add `debug` option that sends graphics with responses enabled and logs `TermResponse` replies; verify `OK` replies are logged in Ghostty

## 3. Rendering and cache

- [x] 3.1 Read PNG IHDR dimensions and cache aspect ratio per source hash; verify with a busted test against `test-files/flowchart.mmd` output
- [x] 3.2 Replace per-viewer temp files with a cache keyed by source hash + size + theme under a plugin temp dir, cleaned on VimLeavePre; verify a second render of identical source does not invoke `mmdr` (spy on `vim.system`)
- [x] 3.3 Compute inline and float target sizes (fixed height, width by aspect, shrink to text width, 297-cell and 10000px caps); verify with busted tests for tall, wide and oversized diagrams
- [x] 3.4 Pass the configured theme to every render; verify `theme = "dark"` appears in the `mmdr` arguments for inline and viewer renders

## 4. Block tracking

- [x] 4.1 Rework `source.lua` to return all mermaid blocks with ranges (treesitter, line-scan fallback) and to extract a block by anchor; verify existing `source_spec.lua` passes plus new cases for multiple blocks and non-mermaid blocks
- [x] 4.2 Anchor each block with an extmark on its opening fence and rescan on debounced `TextChanged`/`TextChangedI`; verify inserting lines above a block keeps the same anchor and editing one block re-renders only that block

## 5. Inline rendering

- [x] 5.1 Create `inline.lua`: render visible blocks (plus one screen margin) as `virt_lines_above` placeholder rows on `BufWinEnter`/`WinScrolled`/rescan; verify in Ghostty with `dev/mermaid-test.md` that all five diagrams appear above their fences and scroll with the text
- [x] 5.2 Double-buffered inline updates: keep the old image until the new one is transmitted, then swap and release; verify editing a block shows no blank gap
- [x] 5.3 Inline error indicator (single line with `mmdr` error, no per-keystroke notifications); verify with the broken diagram in `dev/mermaid-test.md`, then fix it and see the diagram replace the indicator
- [x] 5.4 `:MermaidInline` per-buffer toggle and `inline.enabled` / `inline.height` config; verify toggling clears and restores diagrams in one buffer only, and `height = 10` yields 10-row diagrams
- [x] 5.5 Document inline rendering, `:MermaidInline` and the `inline` options in README.md; verify the documented config example works as written

## 6. Collapse

- [x] 6.1 Implement collapse toggle with the mechanism chosen in 1.2, including the `··· N lines (mermaid)` marker below the diagram; verify toggling on a block, its diagram row and its marker
- [x] 6.2 Expand on entering insert/visual on a collapsed block and re-collapse on returning to normal with the cursor outside it; verify `j`/`k` over a collapsed block keeps it collapsed and `i` on the marker expands it
- [x] 6.3 `:MermaidCollapse` command and `<Plug>(mermaid-viewer-collapse-toggle)`; document both in README.md and verify the "no block under cursor" notification

## 7. Floating viewer

- [x] 7.1 Rebuild the viewer float as a nowrap placeholder buffer (no number/sign columns, `scrolloff=0`), opening for the block under the cursor including diagram rows and collapse markers; verify `<leader>um` on a collapsed block's marker opens that diagram
- [x] 7.2 Bind the viewer to the block anchor so zoom and auto-update use it; verify zooming and editing the block with focus in the float both re-render in a markdown buffer (previous bug)
- [x] 7.3 Zoom (`+`/`=`, `-`, `0`) rebuilds the grid, keeps the centered cell centered, respects max zoom and the 297-cell cap; verify centered content stays centered across zoom steps
- [x] 7.4 Remove custom pan keymaps and `pan_step`; warn once on removed config keys; verify `hjkl`, `zh`/`zl`, `<C-d>` and the mouse wheel move the view and stop at the edges; update `config_spec.lua`
- [x] 7.5 Tear down viewer state on `WinClosed` of the float; verify `:q` on the float removes the image and `:MermaidView` reopens it
- [x] 7.6 Update README.md viewer section (native motions, zoom keys, removed pan options) and verify the documented keys match the defaults

## 8. Plugin interface and health

- [x] 8.1 Add `<Plug>(mermaid-viewer-inline-toggle)` and register `:MermaidInline`/`:MermaidCollapse` in `plugin/mermaid-viewer.lua`; verify all commands and `<Plug>` maps exist after startup
- [x] 8.2 Update `health.lua`: Neovim ≥ 0.12, `mmdr` version, terminal placeholder support, `termguicolors`; drop image.nvim; verify `:checkhealth mermaid-viewer` output in Ghostty and with an unsupported `TERM_PROGRAM`

## 9. KoalaVim integration

- [x] 9.1 Update the mermaid-viewer spec in KoalaVim `lua/KoalaVim/plugins/lsp/servers/markdown.lua`: keep `<leader>um`, add `<leader>ui` (`:MermaidInline`) and `<leader>uc` (`:MermaidCollapse`) for markdown; verify the three keys appear with descriptions in which-key in a markdown buffer

## 10. Integration checks

- [x] 10.1 End-to-end in Ghostty with `dev/mermaid-test.md`: inline diagrams, collapse/expand, editing, viewer open/zoom/scroll/close, toggling inline off and on; verify no stray images remain after closing the buffer
- [x] 10.2 Same walkthrough inside herdr (or confirm herdr is reported unsupported per 1.1)
- [x] 10.3 Performance check on a document with 20 mermaid blocks: scrolling triggers no `mmdr` calls once blocks are cached, and opening the file renders only visible blocks

## Workflow follow-up

- Bump the KoalaVim lockfile pin to the plugin commit that completes this change.
- Archive the change after review and verify the archived specs.
