vim.defer_fn(function()
  local root = vim.fn.tempname()
  local api = vim.api
  local ok, err = xpcall(function()
    vim.fn.mkdir(root, 'p')
    vim.fn.writefile({}, root .. '/requirements.txt')
    vim.fn.writefile({ 'def greet(name: str) -> str:', '    return "Hello " + name' }, root .. '/helpers.py')
    vim.fn.writefile({ 'from helpers import greet', 'result = greet(42)' }, root .. '/main.py')
    vim.cmd.edit(root .. '/main.py')
    local buf = api.nvim_get_current_buf()
    local client
    assert(vim.wait(15000, function()
      client = vim.lsp.get_clients({ bufnr = buf, name = 'basedpyright' })[1]
      return client and client.initialized
    end), 'BasedPyright did not attach')
    assert(vim.uv.fs_realpath(client.root_dir) == vim.uv.fs_realpath(root), 'wrong Python project root')
    local params = { textDocument = { uri = vim.uri_from_bufnr(buf) }, position = { line = 1, character = 10 } }
    local hover = client:request_sync('textDocument/hover', params, 10000, buf)
    assert(hover and not hover.err and hover.result and hover.result.contents, 'hover returned no type information')
    assert(vim.inspect(hover.result.contents):find('name: str', 1, true), 'hover omitted parameter type')
    local definition = client:request_sync('textDocument/definition', params, 10000, buf)
    assert(definition and not definition.err and definition.result, 'definition request failed')
    local target = definition.result[1] or definition.result
    assert((target.uri or target.targetUri):match('/helpers%.py$'), 'definition did not resolve project import')
    assert(vim.wait(10000, function()
      for _, item in ipairs(vim.diagnostic.get(buf)) do
        if item.code == 'reportArgumentType' then return true end
      end
    end), 'type error diagnostic missing')
    assert(vim.fn.maparg('gd', 'n', false, true).desc == 'LSP: go to definition')
    assert(not vim.bo[buf].modified, 'LSP changed the source')
    local snapshot = api.nvim_create_buf(false, true)
    api.nvim_buf_set_name(snapshot, 'diffview://example/old/main.py')
    api.nvim_set_current_buf(snapshot)
    vim.bo[snapshot].filetype = 'python'
    vim.wait(200, function() return false end)
    assert(#vim.lsp.get_clients({ bufnr = snapshot }) == 0, 'historical snapshot attached as a working-tree document')
    client:stop()
    assert(vim.wait(5000, function() return client:is_stopped() end), 'language server did not stop')
  end, debug.traceback)
  vim.fn.delete(root, 'rf')
  if not ok then print(err); vim.cmd('cquit') end
  print('PASS: native Python LSP attach, project root, hover, imported definition, diagnostics and snapshot isolation.')
  vim.cmd('qa!')
end, 100)
