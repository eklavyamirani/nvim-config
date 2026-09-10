local api = vim.api
local config_root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(config_root)
vim.g.mapleader = ' '
vim.o.columns, vim.o.lines = 220, 70
vim.cmd.packadd('plenary.nvim')
vim.cmd.packadd('diffview.nvim')
require('diffview').setup({ use_icons = false,
  keymaps = { file_panel = require('config.review_route').file_panel_keymaps() } })
local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
local function git(...)
  local args = { 'git', '-C', root }
  vim.list_extend(args, { ... })
  local out = vim.system(args, { text = true }):wait()
  assert(out.code == 0, out.stderr)
  return vim.trim(out.stdout)
end
git('init', '--quiet')
git('config', 'user.name', 'Review test')
git('config', 'user.email', 'review@example.invalid')
vim.fn.writefile({ 'return "before"' }, root .. '/a-entry.lua')
vim.fn.writefile({ 'return 1' }, root .. '/b-logic.lua')
vim.fn.writefile({ 'assert(true)' }, root .. '/c-test.lua')
git('add', '.')
git('commit', '-qm', 'base')
local base = git('rev-parse', 'HEAD')
vim.fn.writefile({ 'return require("b-logic")' }, root .. '/a-entry.lua')
local large_diff = { 'local behavior_marker = true' }
for i = 1, 800 do large_diff[#large_diff + 1] = '-- supporting logic ' .. i .. string.rep('x', 60) end
large_diff[#large_diff + 1] = 'return 2'
vim.fn.writefile(large_diff, root .. '/b-logic.lua')
vim.fn.writefile({ 'assert(require("b-logic") == 2)' }, root .. '/c-test.lua')
git('add', '.')
git('commit', '-qm', 'change')
local head = git('rev-parse', 'HEAD')
vim.cmd.cd(root)
vim.cmd('DiffviewOpen ' .. base .. '...' .. head)
local lib = require('diffview.lib')
assert(vim.wait(5000, function()
  local v = lib.get_current_view()
  return v and v.initialized and v.files:len() == 3 and v.cur_entry and v.cur_entry.opened
end), 'Diffview did not initialize')
local view = lib.get_current_view()
local route = require('config.review_route')
local seen_prompt, requests = nil, 0
local response = { groups = {
  { title = 'Specify the behavior', why = 'Does the assertion describe the changed result?', ids = { 3 } },
  { title = 'Trace the implementation', why = 'Does the entry point use the changed logic?', ids = { 1, 2 } },
} }
route.setup({ command = function(prompt)
  requests = requests + 1
  seen_prompt = prompt
  return { 'python3', '-c', 'import sys; print(sys.argv[1])', vim.json.encode(response) }
end })
local notifications = {}
vim.notify = function(message) notifications[#notifications + 1] = message end
local function order()
  local paths = {}
  for _, file in ipairs(view.panel:ordered_file_list()) do paths[#paths + 1] = file.path end
  return table.concat(paths, ',')
end
local function mode()
  local lines = api.nvim_buf_get_lines(view.panel.bufid, 0, -1, false)
  return table.concat(lines, '\n'):match('Order: (%w+)')
end
local function on_path(path)
  route.open()
  for _, file in view.files:iter() do
    if file.path == path then view.panel:highlight_file(file); return end
  end
  error('Missing path: ' .. path)
end
local function press(key)
  assert(vim.bo.filetype == 'DiffviewFiles', 'action outside native file panel')
  vim.fn.maparg(key, 'n', false, true).callback()
end
local function status(path)
  local line
  for _, comp in ipairs(view.panel.components.working.files.comp.components) do
    if comp.context.path == path then line = comp.lstart end
  end
  local ns = api.nvim_get_namespaces()['review-file-status']
  for _, mark in ipairs(api.nvim_buf_get_extmarks(view.panel.bufid, ns, 0, -1, { details = true })) do
    if mark[2] == line then return mark[4].virt_text[1][1] end
  end
end
local function ready(path)
  return vim.wait(3000, function()
    local win = view.cur_layout:get_main_win()
    return view.panel.cur_file.path == path and view.cur_entry == view.panel.cur_file and view.cur_entry.opened
      and api.nvim_buf_get_name(api.nvim_win_get_buf(win.id)):sub(-#path) == path
  end)
end
local original_panel, window_count = view.panel.bufid, #api.nvim_list_wins()
route.open()
assert(view.panel.bufid == original_panel and #api.nvim_list_wins() == window_count, 'created another panel/window')
assert(vim.bo.filetype == 'DiffviewFiles', 'not the native file panel')
assert(requests == 0, 'opening panel must not call AI')
assert(order() == 'a-entry.lua,b-logic.lua,c-test.lua')
assert(status('a-entry.lua') == '[todo] ', 'unreviewed label missing')
assert(mode() == 'Default', 'active order is not visible in panel')
press('g?')
local help = table.concat(api.nvim_buf_get_lines(0, 0, -1, false), '\n')
for _, mapping in ipairs(route.file_panel_keymaps()) do
  assert(help:find(mapping[4].desc, 1, true), 'native help missing ' .. mapping[2])
end
vim.cmd.close()
route.open()
on_path('c-test.lua'); press('md'); press('K'); press('K')
assert(order() == 'c-test.lua,a-entry.lua,b-logic.lua', 'panel did not reorder')
assert(mode() == 'Custom', 'moving a file did not select custom order')
press('gd')
assert(order() == 'a-entry.lua,b-logic.lua,c-test.lua' and mode() == 'Default')
assert(status('c-test.lua') == '[done] ', 'switching orders lost status')
press('gc')
assert(order() == 'c-test.lua,a-entry.lua,b-logic.lua', 'switching lost custom order')
assert(status('c-test.lua') == '[done] ', 'done label did not follow moved file')
assert(view.files[1].path == 'a-entry.lua', 'canonical Git file list was mutated')
on_path('a-entry.lua'); press('ml')
assert(status('a-entry.lua') == '[later] ', 'later label missing')
press('mn'); assert(status('a-entry.lua') == '[todo] ', 'reset label failed')
press('ml')
-- Native Enter and Tab navigate in the same order shown by the file panel.
on_path('c-test.lua'); press('<CR>'); assert(ready('c-test.lua'))
press('<Tab>'); assert(ready('a-entry.lua'), 'native next-file ignored custom order')
press('<S-Tab>'); assert(ready('c-test.lua'), 'native previous-file ignored custom order')
-- Refresh must keep the live file objects and review order/status.
local original_file = view.files[1]
local refreshed = false
view:update_files(function(err) assert(not err); refreshed = true end)
assert(vim.wait(5000, function() return refreshed end), 'refresh did not finish')
assert(order() == 'c-test.lua,a-entry.lua,b-logic.lua', 'refresh reset order')
assert(view.files[1] == original_file, 'refresh unnecessarily recreated source buffers')
assert(status('c-test.lua') == '[done] ' and status('a-entry.lua') == '[later] ')
view.panel:close(); route.open()
assert(view.panel.bufid == original_panel and requests == 0, 'toggle replaced native panel or called AI')
assert(status('a-entry.lua') == '[later] ')
-- Optional suggestions operate in this same panel and retain review states.
local initial_notifications = #notifications
press('go')
assert(vim.wait(5000, function() return requests == 1 and #notifications > initial_notifications end), 'no suggestion result: ' .. vim.inspect(notifications))
assert(requests == 1)
assert(seen_prompt:find(base, 1, true) and seen_prompt:find(head, 1, true))
assert(seen_prompt:find('+return 2', 1, true))
assert(seen_prompt:find('+local behavior_marker = true', 1, true), 'large diff lost its beginning')
assert(seen_prompt:find('[... omitted ...]', 1, true), 'large diff was not sampled')
assert(#seen_prompt < 16000, 'sampled prompt exceeded its bounded budget')
assert(order() == 'c-test.lua,a-entry.lua,b-logic.lua', 'group order did not reach the panel')
assert(mode() == 'AI', 'suggestion did not select AI order')
local function group_lines()
  local lines = {}
  local ns = api.nvim_get_namespaces()['review-file-groups']
  for _, mark in ipairs(api.nvim_buf_get_extmarks(view.panel.bufid, ns, 0, -1, { details = true })) do
    for _, line in ipairs(mark[4].virt_lines or {}) do lines[#lines + 1] = line[1][1] end
  end
  return table.concat(lines, '\n')
end
assert(group_lines():find('Specify the behavior', 1, true), 'group heading hidden')
assert(group_lines():gsub('\n', ' '):find('Does the assertion describe the changed result?', 1, true), 'group question hidden')
assert(group_lines():find('Trace the implementation', 1, true), 'second group heading hidden')
assert(status('c-test.lua') == '[done] ' and status('a-entry.lua') == '[later] ')
assert(vim.bo.filetype == 'DiffviewFiles', 'suggestion opened a different panel')
on_path('c-test.lua'); press('<CR>'); assert(ready('c-test.lua'))
press('<Tab>'); assert(ready('a-entry.lua'), 'group headings broke next-file navigation')
on_path('a-entry.lua'); press('J')
assert(order() == 'c-test.lua,b-logic.lua,a-entry.lua' and mode() == 'Custom')
assert(group_lines() == '', 'AI groups leaked into custom order')
press('ga')
assert(order() == 'c-test.lua,a-entry.lua,b-logic.lua' and mode() == 'AI', 'manual edit changed saved AI order')
assert(requests == 1, 'selecting saved AI order called the assistant')
press('gs')
assert(order() == 'c-test.lua,b-logic.lua,a-entry.lua' and mode() == 'Custom', 'cycle lost custom order')
press('gs')
assert(order() == 'a-entry.lua,b-logic.lua,c-test.lua' and mode() == 'Default')
press('gs')
assert(order() == 'c-test.lua,a-entry.lua,b-logic.lua' and mode() == 'AI')
assert(status('c-test.lua') == '[done] ' and status('a-entry.lua') == '[later] ')
local count = #notifications
response = { groups = { { title = 'Duplicate', why = 'Check?', ids = { 1, 1, 2, 3 } } } }
press('go')
assert(vim.wait(5000, function() return #notifications > count end))
assert(notifications[#notifications]:find('duplicate or unknown', 1, true))
assert(order() == 'c-test.lua,a-entry.lua,b-logic.lua', 'invalid suggestion replaced order')
-- An incomplete plan must not turn into an arbitrary tail of omitted files.
count = #notifications
response = { groups = { { title = 'Incomplete', why = 'Check?', ids = { 1 } } } }
press('go')
assert(vim.wait(5000, function() return #notifications > count end))
assert(notifications[#notifications]:find('omitted 2 file(s)', 1, true))
assert(order() == 'c-test.lua,a-entry.lua,b-logic.lua' and mode() == 'AI', 'incomplete plan replaced saved order')
-- A manual move wins over a pending response.
route.setup({ command = function()
  return { 'python3', '-c', 'import time; time.sleep(0.5); print(\'{"groups":[{"title":"Behavior","why":"Check?","ids":[1,2,3]}]}\')' }
end })
on_path('c-test.lua'); press('go'); press('J')
vim.wait(700, function() return false end)
assert(order() == 'a-entry.lua,c-test.lua,b-logic.lua', 'late suggestion overwrote a manual move')
-- Close and reopen the actual view: automatic attachment restores persisted state.
vim.cmd('DiffviewClose')
vim.cmd('DiffviewOpen ' .. base .. '...' .. head)
assert(vim.wait(5000, function()
  local v = lib.get_current_view()
  return v and v.initialized and v.files:len() == 3 and v.cur_entry and v.cur_entry.opened
end))
view = lib.get_current_view()
assert(order() == 'a-entry.lua,c-test.lua,b-logic.lua', 'saved order not restored automatically')
assert(mode() == 'Custom', 'active order not restored automatically')
assert(status('c-test.lua') == '[done] ' and status('a-entry.lua') == '[later] ', 'saved statuses not restored')
route.open(); press('ga')
assert(order() == 'c-test.lua,a-entry.lua,b-logic.lua' and mode() == 'AI', 'saved AI order not restored')
assert(group_lines():find('Specify the behavior', 1, true), 'saved group heading not restored')
press('gd')
assert(order() == 'a-entry.lua,b-logic.lua,c-test.lua' and mode() == 'Default')
press('gc')
assert(order() == 'a-entry.lua,c-test.lua,b-logic.lua' and mode() == 'Custom', 'saved custom order not restored')
-- A fresh Neovim process must restore all three orders without another AI call.
local resume_script = root .. '/resume-test.lua'
vim.fn.writefile(vim.split(([=[
vim.defer_fn(function()
  local ok, err = xpcall(function()
    require('config.review_route').setup({ command = function() error('saved AI order triggered a request') end })
    vim.cmd('DiffviewOpen ' .. %q .. '...' .. %q)
    local lib = require('diffview.lib')
    assert(vim.wait(5000, function()
      local v = lib.get_current_view()
      return v and v.initialized and v.cur_entry and v.cur_entry.opened
    end))
    local panel = lib.get_current_view().panel
    local function check(expected_mode, expected_order)
      local paths = {}
      for _, file in ipairs(panel:ordered_file_list()) do paths[#paths + 1] = file.path end
      assert(table.concat(paths, ',') == expected_order, 'restart lost ' .. expected_mode .. ' order')
      local lines = table.concat(vim.api.nvim_buf_get_lines(panel.bufid, 0, -1, false), '\n')
      assert(lines:find('Order: ' .. expected_mode, 1, true), 'restart lost active order')
    end
    check('Custom', 'a-entry.lua,c-test.lua,b-logic.lua')
    require('config.review_route').open()
    vim.fn.maparg('ga', 'n', false, true).callback()
    check('AI', 'c-test.lua,a-entry.lua,b-logic.lua')
    vim.fn.maparg('gd', 'n', false, true).callback()
    check('Default', 'a-entry.lua,b-logic.lua,c-test.lua')
    vim.fn.maparg('gc', 'n', false, true).callback()
    check('Custom', 'a-entry.lua,c-test.lua,b-logic.lua')
    local ns = vim.api.nvim_get_namespaces()['review-file-status']
    local labels = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(panel.bufid, ns, 0, -1, { details = true })) do
      labels[#labels + 1] = mark[4].virt_text[1][1]
    end
    assert(table.concat(labels, ',') == '[later] ,[done] ,[todo] ', 'restart lost review statuses')
    vim.cmd.DiffviewClose()
  end, debug.traceback)
  if not ok then print(err); vim.cmd('cquit') end
  vim.cmd('qa!')
end, 100)
]=]):format(base, head), '\n'), resume_script)
local resumed = vim.system({ vim.v.progpath, '--headless', '-u', config_root .. '/init.lua',
  '-c', 'lua dofile(' .. string.format('%q', resume_script) .. ')' }, { cwd = root, text = true, timeout = 15000 }):wait()
vim.fn.delete(resume_script)
assert(resumed.code == 0, 'fresh process failed: ' .. (resumed.stderr or '') .. (resumed.stdout or ''))
-- New compared commits have their own review state.
vim.cmd('DiffviewClose')
git('commit', '--allow-empty', '-qm', 'new revision')
local other_head = git('rev-parse', 'HEAD')
vim.cmd('DiffviewOpen ' .. base .. '...' .. other_head)
assert(vim.wait(5000, function()
  local v = lib.get_current_view()
  return v and v.initialized and v.files:len() == 3 and v.cur_entry and v.cur_entry.opened
end))
view = lib.get_current_view()
assert(order() == 'a-entry.lua,b-logic.lua,c-test.lua', 'different comparison reused order')
assert(status('c-test.lua') == '[todo] ' and status('a-entry.lua') == '[todo] ', 'different comparison reused completion state')
vim.cmd('DiffviewClose')
-- Migrate the previous one-order format without losing order or old read marks.
local state_dir = vim.fn.stdpath('state') .. '/review-context/' .. vim.fn.sha256(vim.uv.fs_realpath(root)):sub(1, 20)
local signature = base .. ':' .. other_head .. ':working:a-entry.lua\nworking:b-logic.lua\nworking:c-test.lua'
local saved_path = state_dir .. '/route-' .. vim.fn.sha256(signature):sub(1, 20) .. '.json'
vim.fn.writefile({ vim.json.encode({ signature = signature, items = {
  { key = 'working:c-test.lua', read = true }, { key = 'working:a-entry.lua', status = 'later' },
  { key = 'working:b-logic.lua', status = 'todo' },
} }) }, saved_path)
vim.cmd('DiffviewOpen ' .. base .. '...' .. other_head)
assert(vim.wait(5000, function()
  local v = lib.get_current_view()
  return v and v.initialized and v.cur_entry and v.cur_entry.opened
end))
view = lib.get_current_view()
assert(mode() == 'Custom' and order() == 'c-test.lua,a-entry.lua,b-logic.lua', 'legacy order was not migrated')
assert(status('c-test.lua') == '[done] ' and status('a-entry.lua') == '[later] ', 'legacy marks were not migrated')
route.open(); press('gd'); press('gc')
assert(order() == 'c-test.lua,a-entry.lua,b-logic.lua', 'switching lost migrated order')
vim.cmd('DiffviewClose')
vim.fn.delete(root, 'rf')
print('PASS: native help, three saved orders, shared statuses, navigation, refresh, fresh-process resume, legacy migration, comparison isolation and AI cancellation.')
vim.cmd('qa!')
