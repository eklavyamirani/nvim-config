vim.defer_fn(function()
  local api = vim.api
  local root = vim.fn.tempname()
  local ok, err = xpcall(function()
    vim.o.columns, vim.o.lines = 160, 50
    vim.o.clipboard = ''
    vim.fn.mkdir(root .. '/a-very-long-directory-name/another-long-directory-name', 'p')
    local function git(...)
      local args = { 'git', '-C', root }
      vim.list_extend(args, { ... })
      local result = vim.system(args, { text = true }):wait()
      assert(result.code == 0, result.stderr)
      return vim.trim(result.stdout)
    end
    git('init', '--quiet'); git('config', 'user.name', 'Review test'); git('config', 'user.email', 'review@example.invalid')
    local lines = {}
    for i = 1, 220 do lines[i] = 'local value_' .. i .. ' = ' .. i end
    vim.fn.writefile(lines, root .. '/modified.lua')
    git('add', '.'); git('commit', '-qm', 'base')
    local base = git('rev-parse', 'HEAD')
    local added = 'a-very-long-directory-name/another-long-directory-name/new-file-with-a-very-long-name.lua'
    vim.fn.writefile(lines, root .. '/' .. added)
    lines[110] = 'local value_110 = 111'
    vim.fn.writefile(lines, root .. '/modified.lua')
    git('add', '.'); git('commit', '-qm', 'change')
    vim.cmd.cd(root)
    vim.cmd('DiffviewOpen ' .. base .. '...HEAD')
    local view
    local function ready(path)
      return vim.wait(5000, function()
        view = require('diffview.lib').get_current_view()
        return view and view.initialized and view.cur_entry and view.cur_entry.path == path
          and view.cur_entry.opened and not view._review_loading
      end)
    end
    assert(ready(added), 'new file did not open')
    local function open(path)
      view:set_file_by_path(path, true, true)
      assert(ready(path))
    end
    assert(#view.cur_layout.windows == 1, 'new file wasted a before pane')
    assert(vim.wo[view.panel.winid].wrap and vim.wo[view.panel.winid].linebreak, 'panel rows do not wrap')
    local panel_text = table.concat(api.nvim_buf_get_lines(view.panel.bufid, 0, -1, false), '\n')
    assert(panel_text:find('new-file-with-a-very-long-name.lua', 1, true), 'panel lost full filename')
    open(added)
    local win = view.cur_layout:get_main_win().id
    api.nvim_win_set_cursor(win, { 83, 4 })
    api.nvim_win_call(win, function() vim.cmd('normal! zt'); vim.cmd('normal! mA') end)
    local position = api.nvim_win_call(win, vim.fn.winsaveview)
    open('modified.lua')
    assert(#view.cur_layout.windows == 2, 'modified file lost comparison')
    open(added)
    assert(#view.cur_layout.windows == 1, 'empty pane returned after navigation')
    local restored = api.nvim_win_call(view.cur_layout:get_main_win().id, vim.fn.winsaveview)
    assert(restored.lnum == position.lnum and restored.col == position.col, 'navigation reset cursor')
    assert(restored.topline == position.topline, 'navigation reset scroll position')
    open('modified.lua')
    vim.cmd("normal! 'A")
    assert(ready(added), 'mark jump did not select its Diffview entry')
    assert(#view.cur_layout.windows == 1, 'mark jump restored empty pane')
    assert(api.nvim_win_get_cursor(view.cur_layout:get_main_win().id)[1] == 83, 'mark jump reset cursor')
    local refreshed = false
    view:update_files(function(failure) assert(not failure); refreshed = true end)
    assert(vim.wait(5000, function() return refreshed and not view._review_loading end))
    assert(#view.cur_layout.windows == 1, 'refresh restored empty pane')
    assert(api.nvim_win_get_cursor(view.cur_layout:get_main_win().id)[1] == 83, 'refresh reset cursor')
    local message = 'Copyable error fixture\n  traceback line one\n  traceback line two'
    vim.notify(message, vim.log.levels.ERROR)
    assert(vim.wait(2000, function()
      for _, item in ipairs(require('mini.notify').get_all()) do if item.msg == message then return true end end
    end))
    local diff_tab = view.tabpage
    vim.cmd.Notifications()
    assert(api.nvim_get_current_tabpage() ~= diff_tab, 'history replaced a diff pane')
    assert(vim.bo.filetype == 'mininotify-history')
    local history = table.concat(api.nvim_buf_get_lines(0, 0, -1, false), '\n')
    assert(history:find('traceback line two', 1, true), 'history lost multiline error')
    vim.cmd('normal! ggVGy')
    assert(vim.fn.getreg('"'):find('Copyable error fixture', 1, true), 'notification history cannot be yanked')
    vim.cmd.close()
    api.nvim_set_current_tabpage(diff_tab)
    vim.cmd.DiffviewClose()
    vim.cmd('delmarks A')
  end, debug.traceback)
  vim.fn.delete(root, 'rf')
  if not ok then print(err); vim.cmd('cquit') end
  print('PASS: wrapped panel paths, added-file single panes, cursor/scroll preservation, marks, refresh and copyable notifications.')
  vim.cmd('qa!')
end, 100)
