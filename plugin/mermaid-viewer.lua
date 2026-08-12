if vim.g.loaded_mermaid_viewer then
  return
end
vim.g.loaded_mermaid_viewer = true

vim.api.nvim_create_user_command("MermaidView", function()
  require("mermaid-viewer").view()
end, { desc = "Open Mermaid diagram viewer" })

vim.api.nvim_create_user_command("MermaidClose", function()
  require("mermaid-viewer").close()
end, { desc = "Close Mermaid diagram viewer" })

vim.api.nvim_create_user_command("MermaidToggle", function()
  require("mermaid-viewer").toggle()
end, { desc = "Toggle Mermaid diagram viewer" })

vim.keymap.set("n", "<Plug>(mermaid-viewer-view)", function()
  require("mermaid-viewer").view()
end, { desc = "Open Mermaid diagram viewer" })

vim.keymap.set("n", "<Plug>(mermaid-viewer-close)", function()
  require("mermaid-viewer").close()
end, { desc = "Close Mermaid diagram viewer" })

vim.keymap.set("n", "<Plug>(mermaid-viewer-toggle)", function()
  require("mermaid-viewer").toggle()
end, { desc = "Toggle Mermaid diagram viewer" })
