vim.defer_fn(function()
  local api = vim.api
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, 'p')
  local function git(...)
    local cmd = { 'git', '-C', root }
    vim.list_extend(cmd, { ... })
    local out = vim.system(cmd, { text = true }):wait()
    assert(out.code == 0, out.stderr)
    return vim.trim(out.stdout)
  end
  local function write(path, lines) vim.fn.writefile(lines, root .. '/' .. path) end
  local function mapped(key)
    local map = vim.fn.maparg(key, 'n', false, true)
    assert(map.callback, 'missing ' .. key .. ' mapping')
    map.callback()
  end
  local ok, err = xpcall(function()
    git('init', '-q')
    git('config', 'user.email', 'test@example.invalid')
    git('config', 'user.name', 'Test')
    write('requirements.txt', {})
    write('stable.py', { 'def stable():', '    return "unchanged"' })
    write('helpers.py', { 'def greet(name: str) -> str:', '    return "base " + name' })
    write('main.py', { 'from helpers import greet', 'from stable import stable', 'result = greet("base")', 'other = stable()' })
    git('add', '.')
    git('commit', '-qm', 'base')
    local base = git('rev-parse', 'HEAD')
    write('helpers.py', { '# Reviewed version', '', 'def greet(name: str) -> str:', '    return "reviewed " + name' })
    write('main.py', { 'from helpers import greet', 'from stable import stable', 'result = greet("reviewed")', 'other = stable()', 'from z_added import added', 'new = added()' })
    write('z_added.py', { '# A new, initially unopened definition', 'def added():', '    return 42' })
    git('add', '.')
    git('commit', '-qm', 'reviewed')
    local reviewed = git('rev-parse', 'HEAD')
    write('helpers.py', { '# Different checkout', '', '', '', 'def greet(name: int) -> int:', '    return name + 42' })
    git('add', '.')
    git('commit', '-qm', 'later')
    vim.cmd.cd(root)
    vim.cmd('DiffviewOpen ' .. base .. '..' .. reviewed)
    local view
    assert(vim.wait(10000, function()
      view = require('diffview.lib').get_current_view()
      return view and view.initialized and view.cur_entry and view.cur_entry.opened
    end), 'diff failed to open')
    local function open(path, symbol)
      view:set_file_by_path(path, true, true)
      assert(vim.wait(5000, function()
        return view.cur_entry.path == path and view.cur_entry.opened and not view._review_loading
      end), 'file failed to open')
      vim.wait(100, function() return false end)
      for _, win in ipairs(view.cur_layout.windows) do
        if win.file.symbol == symbol then api.nvim_set_current_win(win.id); return end
      end
      error('missing revision pane ' .. symbol)
    end
    open('main.py', 'b')
    local diff_tab = api.nvim_get_current_tabpage()
    api.nvim_win_set_cursor(0, { 3, 11 })
    mapped('K')
    assert(vim.wait(20000, function()
      for _, win in ipairs(api.nvim_tabpage_list_wins(diff_tab)) do
        if api.nvim_win_get_config(win).relative ~= '' then
          local text = table.concat(api.nvim_buf_get_lines(api.nvim_win_get_buf(win), 0, -1, false), '\n')
          if text:find('name: str', 1, true) then api.nvim_win_close(win, true); return true end
        end
      end
    end), 'historical hover did not use str signature')
    mapped('gd')
    assert(vim.wait(15000, function()
      return view.cur_entry.path == 'helpers.py' and api.nvim_win_get_cursor(0)[1] == 3
    end), 'reviewed definition should be helpers.py:3')
    assert(api.nvim_get_current_tabpage() == diff_tab, 'jump left Diffview')
    assert(api.nvim_get_current_line() == 'def greet(name: str) -> str:', 'definition came from checkout')
    mapped('<C-t>')
    assert(vim.wait(5000, function() return view.cur_entry.path == 'main.py' and api.nvim_win_get_cursor(0)[1] == 3 end), 'return lost source position')
    api.nvim_win_set_cursor(0, { 4, 10 })
    mapped('gd')
    assert(vim.wait(10000, function() return vim.b.diffview_lsp and vim.b.diffview_lsp.path == 'stable.py' end), 'unchanged definition did not open')
    assert(api.nvim_get_current_tabpage() == diff_tab and not vim.bo.modifiable and vim.bo.readonly, 'source pane must be read-only in same tab')
    mapped('<C-t>')
    assert(api.nvim_win_get_cursor(0)[1] == 4 and api.nvim_get_current_line() == 'other = stable()', 'return from unchanged file failed')
    open('main.py', 'a')
    api.nvim_win_set_cursor(0, { 3, 11 })
    mapped('gd')
    assert(vim.wait(20000, function()
      return view.cur_entry.path == 'helpers.py' and api.nvim_win_get_cursor(0)[1] == 1
        and api.nvim_get_current_line() == 'def greet(name: str) -> str:'
    end), 'before-side definition should be helpers.py:1')
    open('main.py', 'b')
    api.nvim_win_set_cursor(0, { 6, 8 })
    mapped('gd')
    assert(vim.wait(10000, function()
      return view.cur_entry.path == 'z_added.py' and api.nvim_win_get_cursor(0)[1] == 2
    end), 'definition in an unopened added file lost its target position')
    assert(git('status', '--porcelain') == '', 'source repository changed')
    vim.cmd.DiffviewClose()
  end, debug.traceback)
  for _, client in ipairs(vim.lsp.get_clients()) do client:stop(true) end
  vim.fn.delete(root, 'rf')
  if not ok then print(err); vim.cmd('cquit') end
  print('PASS: historical hover, both revision definitions, unchanged source pane, return positions, clean checkout.')
  vim.cmd('qa!')
end, 100)
