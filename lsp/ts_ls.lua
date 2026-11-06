return {
  -- TypeScript 7 ships its language server inside the compiler binary.
  cmd = { require('config.lsp_servers').executable('ts_ls'), '--lsp', '--stdio' },
  filetypes = { 'typescript', 'typescriptreact', 'javascript', 'javascriptreact' },
  root_markers = { { 'tsconfig.json', 'jsconfig.json' }, 'package.json', '.git' },
  on_attach = function(client, buf)
    vim.diagnostic.config({ signs = false }, vim.lsp.diagnostic.get_namespace(client.id))
    vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { buffer = buf, desc = 'LSP: go to definition' })
    vim.keymap.set('n', '<leader>ld', vim.diagnostic.open_float, { buffer = buf, desc = 'LSP: show diagnostic details' })
  end,
}
