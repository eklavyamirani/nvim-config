-- Run with the real init.lua so plugin initialization order is exercised:
-- nvim --headless -u init.lua -c "lua dofile('tests/review_startup.lua')"
vim.defer_fn(function()
  local root = vim.fn.tempname()
  local ok, err = xpcall(function()
    vim.fn.mkdir(root, 'p')
    local function git(...)
      local args = { 'git', '-C', root }
      vim.list_extend(args, { ... })
      local result = vim.system(args, { text = true }):wait()
      assert(result.code == 0, result.stderr)
    end
    git('init', '--quiet')
    git('config', 'user.name', 'Review test')
    git('config', 'user.email', 'review@example.invalid')
    vim.fn.writefile({ 'return 1' }, root .. '/example.lua')
    git('add', '.')
    git('commit', '-qm', 'base')
    git('update-ref', 'refs/remotes/origin/main', 'HEAD')
    git('symbolic-ref', 'refs/remotes/origin/HEAD', 'refs/remotes/origin/main')
    vim.fn.writefile({ 'return 2' }, root .. '/example.lua')
    git('commit', '-qam', 'change')
    vim.cmd.cd(root)

    vim.fn.maparg(' dm', 'n', false, true).callback()
    local lib = require('diffview.lib')
    assert(vim.wait(5000, function()
      local view = lib.get_current_view()
      return view and view.initialized and view.cur_entry and view.cur_entry.opened
    end), 'leader dm did not open a diff')
    local panel = lib.get_current_view().panel
    assert(panel._review_file_order, 'review file panel was not attached')
    assert(panel:ordered_file_list()[1].path == 'example.lua', 'changed file missing')
    local ns = vim.api.nvim_get_namespaces()['review-file-status']
    local marks = vim.api.nvim_buf_get_extmarks(panel.bufid, ns, 0, -1, { details = true })
    assert(#marks == 1 and marks[1][4].virt_text[1][1] == '[todo] ', 'review status missing')
    vim.cmd.DiffviewClose()
  end, debug.traceback)
  vim.fn.delete(root, 'rf')
  if not ok then print(err); vim.cmd('cquit') end
  print('Review startup test passed')
  vim.cmd('qa!')
end, 100)
