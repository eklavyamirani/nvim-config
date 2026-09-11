return {
  cmd = function(dispatchers, config)
    -- csharp-ls discovers the solution from its working directory.
    return vim.lsp.rpc.start({ require('config.lsp_servers').executable('csharp_ls') }, dispatchers, {
      cwd = config.root_dir,
    })
  end,
  filetypes = { 'cs' },
  root_dir = function(buf, on_dir)
    local function find_root(extensions)
      return vim.fs.root(buf, function(name)
        for _, extension in ipairs(extensions) do
          if vim.endswith(name, extension) then return true end
        end
        return false
      end)
    end
    local root = find_root({ '.sln', '.slnx' }) or find_root({ '.csproj' })
    if root then on_dir(root) end
  end,
  get_language_id = function() return 'csharp' end,
  init_options = { AutomaticWorkspaceInit = true },
  on_attach = function(client, buf)
    vim.diagnostic.config({ signs = false }, vim.lsp.diagnostic.get_namespace(client.id))
    vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { buffer = buf, desc = 'LSP: go to definition' })
    vim.keymap.set('n', '<leader>ld', vim.diagnostic.open_float, { buffer = buf, desc = 'LSP: show diagnostic details' })
  end,
}
