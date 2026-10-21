if vim.g.loaded_mermaid_viewer then
  return
end
vim.g.loaded_mermaid_viewer = true

pcall(function()
  require("mermaid-viewer.inline").setup()
end)

vim.api.nvim_create_user_command("MermaidView", function()
  require("mermaid-viewer").view()
end, { desc = "Open Mermaid diagram viewer" })

vim.api.nvim_create_user_command("MermaidClose", function()
  require("mermaid-viewer").close()
end, { desc = "Close Mermaid diagram viewer" })

vim.api.nvim_create_user_command("MermaidToggle", function()
  require("mermaid-viewer").toggle()
end, { desc = "Toggle Mermaid diagram viewer" })

vim.api.nvim_create_user_command("MermaidInline", function()
  require("mermaid-viewer.inline").toggle(vim.api.nvim_get_current_buf())
end, { desc = "Toggle inline Mermaid diagrams in the buffer" })

vim.api.nvim_create_user_command("MermaidCollapse", function()
  require("mermaid-viewer.collapse").toggle(vim.api.nvim_get_current_buf(), vim.api.nvim_win_get_cursor(0)[1] - 1)
end, { desc = "Toggle collapse of the Mermaid diagram under the cursor" })

vim.keymap.set("n", "<Plug>(mermaid-viewer-view)", function()
  require("mermaid-viewer").view()
end, { desc = "Open Mermaid diagram viewer" })

vim.keymap.set("n", "<Plug>(mermaid-viewer-close)", function()
  require("mermaid-viewer").close()
end, { desc = "Close Mermaid diagram viewer" })

vim.keymap.set("n", "<Plug>(mermaid-viewer-toggle)", function()
  require("mermaid-viewer").toggle()
end, { desc = "Toggle Mermaid diagram viewer" })

vim.keymap.set("n", "<Plug>(mermaid-viewer-inline-toggle)", function()
  require("mermaid-viewer.inline").toggle(vim.api.nvim_get_current_buf())
end, { desc = "Toggle inline Mermaid diagrams in the buffer" })

vim.keymap.set("n", "<Plug>(mermaid-viewer-collapse-toggle)", function()
  require("mermaid-viewer.collapse").toggle(vim.api.nvim_get_current_buf(), vim.api.nvim_win_get_cursor(0)[1] - 1)
end, { desc = "Toggle collapse of the Mermaid diagram under the cursor" })
