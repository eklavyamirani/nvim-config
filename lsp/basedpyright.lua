return {
  cmd = { require('config.lsp_servers').executable('basedpyright'), '--stdio' },
  filetypes = { 'python' },
  root_markers = { 'pyrightconfig.json', 'pyproject.toml', 'setup.py', 'setup.cfg', 'requirements.txt', '.git' },
  settings = {
    basedpyright = {
      disableTaggedHints = true,
      analysis = {
        typeCheckingMode = 'basic',
        autoFormatStrings = false,
        baselineMode = 'discard',
      },
    },
  },
  on_attach = function(client, buf)
    vim.diagnostic.config({ signs = false }, vim.lsp.diagnostic.get_namespace(client.id))
    vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { buffer = buf, desc = 'LSP: go to definition' })
    vim.keymap.set('n', '<leader>ld', vim.diagnostic.open_float, { buffer = buf, desc = 'LSP: show diagnostic details' })
  end,
}
