return {
  cmd = { require('config.lsp_servers').executable('rust_analyzer') },
  filetypes = { 'rust' },
  -- Cargo.lock and rust-project.json sit at the workspace root; a member's
  -- Cargo.toml is only the fallback, so one server covers the whole workspace.
  root_markers = { { 'Cargo.lock', 'rust-project.json' }, 'Cargo.toml', '.git' },
  on_attach = function(client, buf)
    vim.diagnostic.config({ signs = false }, vim.lsp.diagnostic.get_namespace(client.id))
    vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { buffer = buf, desc = 'LSP: go to definition' })
    vim.keymap.set('n', '<leader>ld', vim.diagnostic.open_float, { buffer = buf, desc = 'LSP: show diagnostic details' })
  end,
}
