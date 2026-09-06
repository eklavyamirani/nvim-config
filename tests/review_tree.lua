-- Run after startup, like tests/review_route.lua.
local api = vim.api
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.g.mapleader = ' '
vim.o.columns, vim.o.lines = 180, 60
vim.cmd.packadd('plenary.nvim')
vim.cmd.packadd('diffview.nvim')
local route = require('config.review_route')
require('diffview').setup({ use_icons = false, file_panel = { listing_style = 'list' },
  keymaps = { file_panel = route.file_panel_keymaps() } })
route.setup({ command = function()
  return { 'python3', '-c', 'print(\'{"items":[{"id":2},{"id":1},{"id":3}]}\')' }
end })
local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/z-dir/nested', 'p')
local function git(...)
  local args = { 'git', '-C', root }
  vim.list_extend(args, { ... })
  local result = vim.system(args, { text = true }):wait()
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout)
end
git('init', '--quiet')
git('config', 'user.name', 'Review test')
git('config', 'user.email', 'review@example.invalid')
local paths = { 'a.lua', 'z-dir/b.lua', 'z-dir/nested/c.lua' }
for _, path in ipairs(paths) do vim.fn.writefile({ 'return 1' }, root .. '/' .. path) end
git('add', '.'); git('commit', '-qm', 'base')
local base = git('rev-parse', 'HEAD')
for _, path in ipairs(paths) do vim.fn.writefile({ 'return 2' }, root .. '/' .. path) end
git('commit', '-qam', 'change')
vim.cmd.cd(root)
local view
local function open()
  vim.cmd('DiffviewOpen ' .. base .. '...HEAD')
  assert(vim.wait(5000, function()
    view = require('diffview.lib').get_current_view()
    return view and view.initialized and view.cur_entry and view.cur_entry.opened
  end))
  route.open()
end
local function press(key) vim.fn.maparg(key, 'n', false, true).callback() end
local function order()
  return vim.tbl_map(function(file) return file.path end, view.panel:ordered_file_list())
end
local function select(path)
  for _, file in view.files:iter() do
    if file.path == path then view.panel:highlight_file(file); return end
  end
end
local function marks()
  local result = {}
  local ns = api.nvim_get_namespaces()['review-file-status']
  for _, mark in ipairs(api.nvim_buf_get_extmarks(view.panel.bufid, ns, 0, -1, { details = true })) do
    result[mark[2]] = mark[4].virt_text[1][1]
  end
  return result
end
local function status(path)
  local result
  view.panel.components.working.files.comp:deep_some(function(comp)
    if comp.name == 'file' and comp.context.path == path and comp.height > 0 then result = marks()[comp.lstart] end
  end)
  return result
end
open()
assert(view.panel.listing_style == 'list')
press('i')
assert(view.panel.listing_style == 'tree', 'default order did not allow tree view')
local tree_order = order()
assert(tree_order[1] ~= 'a.lua', 'fixture must distinguish tree and list order')
for _, path in ipairs(paths) do assert(status(path) == '[todo] ', 'nested review label missing: ' .. path) end
select('z-dir/nested/c.lua'); press('md')
assert(status('z-dir/nested/c.lua') == '[done] ')
press('zM')
assert(status('z-dir/nested/c.lua') == nil, 'collapsed file kept its label')
assert(vim.tbl_count(marks()) == 1, 'hidden labels leaked onto folder rows')
press('zR')
assert(status('z-dir/nested/c.lua') == '[done] ', 'expanding lost review mark')
select(tree_order[1]); press('<CR>')
assert(vim.wait(3000, function() return view.cur_entry.path == tree_order[1] and view.cur_entry.opened end))
press('<Tab>')
assert(vim.wait(3000, function() return view.cur_entry.path == tree_order[2] and view.cur_entry.opened end), 'navigation ignored tree order')
select(tree_order[1]); press('J')
assert(view.panel.listing_style == 'list', 'manual move did not switch to flat custom order')
assert(order()[1] == tree_order[2] and order()[2] == tree_order[1], 'manual move did not start from tree order')
local custom_order = order()
press('i'); assert(view.panel.listing_style == 'list', 'custom order allowed tree view')
press('gd'); assert(view.panel.listing_style == 'tree', 'returning to default lost tree preference')
local refreshed = false
view:update_files(function(err) assert(not err); refreshed = true end)
assert(vim.wait(5000, function() return refreshed end))
assert(view.panel.listing_style == 'tree' and status('z-dir/nested/c.lua') == '[done] ', 'refresh lost tree or marks')
press('ga')
assert(vim.wait(5000, function()
  return table.concat(api.nvim_buf_get_lines(view.panel.bufid, 0, -1, false), '\n'):find('Order: AI', 1, true)
end), 'AI order did not arrive')
assert(view.panel.listing_style == 'list', 'AI order did not use flat list')
press('gd'); assert(view.panel.listing_style == 'tree')
vim.cmd.DiffviewClose(); open()
assert(view.panel.listing_style == 'tree', 'saved tree preference not restored')
assert(status('z-dir/nested/c.lua') == '[done] ', 'saved nested status not restored')
press('gc'); assert(vim.deep_equal(order(), custom_order), 'tree toggling lost custom order')
press('gd'); press('i')
assert(view.panel.listing_style == 'list' and vim.deep_equal(order(), paths), 'toggle back did not restore default list order')
vim.cmd.DiffviewClose(); open()
assert(view.panel.listing_style == 'list', 'saved list preference not restored')
vim.cmd.DiffviewClose()
vim.fn.delete(root, 'rf')
print('PASS: default tree/list toggle, nested marks, folding, navigation, custom/AI transitions, refresh and saved layout.')
vim.cmd('qa!')
