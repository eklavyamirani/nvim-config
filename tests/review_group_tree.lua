local api = vim.api
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.g.mapleader = ' '
vim.o.columns, vim.o.lines = 200, 70
vim.cmd.packadd('plenary.nvim'); vim.cmd.packadd('diffview.nvim')
local route = require('config.review_route')
require('diffview').setup({ use_icons = false, watch_index = false,
  keymaps = { file_panel = route.file_panel_keymaps() } })
local requests = 0
route.setup({ command = function()
  requests = requests + 1
  return { 'python3', '-c', 'import sys; print(sys.argv[1])', vim.json.encode({ groups = {
    { title = 'Behavior', why = 'Does this behavior match the contract?', ids = { 3, 1, 4 } },
    { title = 'Operations', why = 'Can this be operated safely?', ids = { 2 } },
  } }) }
end })
local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/shared/nested', 'p')
local function git(...)
  local args = { 'git', '-C', root }
  vim.list_extend(args, { ... })
  local out = vim.system(args, { text = true }):wait()
  assert(out.code == 0, out.stderr)
  return vim.trim(out.stdout)
end
git('init', '--quiet'); git('config', 'user.name', 'Review test'); git('config', 'user.email', 'review@example.invalid')
local paths = { 'a-root.lua', 'shared/a.lua', 'shared/b.lua', 'shared/nested/c.lua' }
for _, path in ipairs(paths) do vim.fn.writefile({ 'return 1' }, root .. '/' .. path) end
git('add', '.'); git('commit', '-qm', 'base')
local base = git('rev-parse', 'HEAD')
for _, path in ipairs(paths) do vim.fn.writefile({ 'return 2' }, root .. '/' .. path) end
git('commit', '-qam', 'change'); vim.cmd.cd(root)
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
local function order() return vim.tbl_map(function(file) return file.path end, view.panel:ordered_file_list()) end
local function select(path)
  if not view.panel:is_focused() then route.open() end
  for _, file in view.files:iter() do if file.path == path then view.panel:highlight_file(file); return end end
end
local function marks(ns)
  return api.nvim_buf_get_extmarks(view.panel.bufid, api.nvim_get_namespaces()[ns], 0, -1, { details = true })
end
local function groups()
  local result = {}
  for _, mark in ipairs(marks('review-file-groups')) do result[#result + 1] = mark[4].virt_lines[1][1][1] end
  return table.concat(result, ',')
end
open(); press('ga')
assert(vim.wait(5000, function() return groups() == 'Behavior,Operations' end), 'group headings missing')
assert(view.panel.listing_style == 'tree')
local tree_order = { paths[3], paths[4], paths[1], paths[2] }
assert(vim.deep_equal(order(), tree_order), 'tree did not preserve groups and directory insertion order')
local shown = {}
view.panel.components.working.files.comp:deep_some(function(comp)
  if comp.name == 'file' then shown[#shown + 1] = comp.context.path end
end)
assert(vim.deep_equal(shown, tree_order), 'navigation disagrees with displayed tree')
local components = view.panel.components.working.files.comp.components
assert(components[1].context.path == 'shared' and components[3].context.path == 'shared', 'shared directories merged across groups')
assert(marks('review-file-groups')[1][2] == components[1].lstart, 'heading appeared inside its directory')
select(paths[3]); press('<CR>')
assert(vim.wait(3000, function() return view.cur_entry.path == paths[3] and view.cur_entry.opened end))
press('<Tab>')
assert(vim.wait(3000, function() return view.cur_entry.path == paths[4] and view.cur_entry.opened end), 'next-file skipped the tree order')
route.open(); press('zM')
assert(groups() == 'Behavior,Operations', 'folding hid group descriptions')
assert(#marks('review-file-status') == 1, 'collapsed files retained visible review labels')
select(paths[1]); press('md')
assert(#marks('review-file-status') == 1, 'marking a file reset unrelated folds')
press('zR'); assert(#marks('review-file-status') == 4)
local refreshed = false
view:update_files(function(err) assert(not err); refreshed = true end)
assert(vim.wait(5000, function() return refreshed end))
assert(vim.deep_equal(order(), tree_order) and groups() == 'Behavior,Operations', 'refresh lost grouped trees')
assert(view.files[1].path == paths[1], 'tree modified canonical Git ordering')
press('i'); assert(view.panel.listing_style == 'list')
assert(vim.deep_equal(order(), { paths[3], paths[1], paths[4], paths[2] }), 'list lost original AI order')
vim.cmd.DiffviewClose(); open()
assert(view.panel.listing_style == 'list' and groups() == 'Behavior,Operations', 'saved AI list preference lost')
press('i'); vim.cmd.DiffviewClose(); open()
assert(view.panel.listing_style == 'tree' and vim.deep_equal(order(), tree_order), 'saved AI tree lost')
assert(requests == 1, 'changing layout called AI')
select(paths[3]); press('J')
assert(view.panel.listing_style == 'list' and groups() == '', 'manual move did not select flat custom order')
assert(vim.deep_equal(order(), { paths[4], paths[3], paths[1], paths[2] }), 'manual move ignored displayed tree order')
press('ga'); assert(vim.deep_equal(order(), tree_order), 'manual move replaced saved AI order')
vim.cmd.DiffviewClose(); vim.fn.delete(root, 'rf')
print('PASS: grouped directory trees, shared paths, descriptions, folding, navigation, refresh, layout persistence and manual moves.')
vim.cmd('qa!')
