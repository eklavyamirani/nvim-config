return {
  cmd = { require('config.lsp_servers').executable('jsonls'), '--stdio' },
  filetypes = { 'json', 'jsonc' },
  root_markers = { 'package.json', '.git' },
  init_options = { provideFormatter = true },
  settings = {
    json = {
      -- Parse errors come from the server regardless; `validate` is what turns
      -- a matched schema into type/shape diagnostics.
      validate = { enable = true },
      -- The server bundles no schemas — VS Code supplies them there — so a
      -- file only gets type checking through its own `$schema` key or a match
      -- here. Schemas are fetched lazily when such a file opens, never at
      -- startup.
      schemas = {
        { fileMatch = { 'package.json' }, url = 'https://json.schemastore.org/package.json' },
        { fileMatch = { 'tsconfig.json', 'tsconfig.*.json' }, url = 'https://json.schemastore.org/tsconfig' },
        { fileMatch = { 'jsconfig.json', 'jsconfig.*.json' }, url = 'https://json.schemastore.org/jsconfig' },
        { fileMatch = { '.eslintrc', '.eslintrc.json' }, url = 'https://json.schemastore.org/eslintrc' },
        { fileMatch = { '.prettierrc', '.prettierrc.json' }, url = 'https://json.schemastore.org/prettierrc' },
        { fileMatch = { '.markdownlint.json', '.markdownlint.jsonc' }, url = 'https://json.schemastore.org/markdownlint' },
        { fileMatch = { '.luarc.json', '.luarc.jsonc' }, url = 'https://raw.githubusercontent.com/LuaLS/vscode-lua/master/setting/schema.json' },
      },
    },
  },
  on_attach = function(client, buf)
    vim.diagnostic.config({ signs = false }, vim.lsp.diagnostic.get_namespace(client.id))
    vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { buffer = buf, desc = 'LSP: go to definition' })
    vim.keymap.set('n', '<leader>ld', vim.diagnostic.open_float, { buffer = buf, desc = 'LSP: show diagnostic details' })
  end,
}
