-- Run after startup, like tests/review_route.lua.
local api = vim.api
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.g.mapleader = ' '
vim.o.columns, vim.o.lines = 200, 70
vim.cmd.packadd('plenary.nvim'); vim.cmd.packadd('diffview.nvim')
local route = require('config.review_route')
require('diffview').setup({ use_icons = false, watch_index = false, file_panel = { listing_style = 'list' },
  keymaps = { file_panel = route.file_panel_keymaps() } })
local prompt, requests, delay = nil, 0, 0
local notifications = {}
vim.notify = function(message) notifications[#notifications + 1] = message end
route.setup({ command = function(text)
  prompt, requests = text, requests + 1
  local groups, sections = {}, {}
  for id, kind in text:gmatch('\nID (%d+) | [^\n]- | section (%w+)') do
    if not sections[kind] then
      sections[kind] = { title = 'Behavior', why = 'Are these changes consistent?', ids = {} }
      groups[#groups + 1] = sections[kind]
    end
    table.insert(sections[kind].ids, 1, tonumber(id))
  end
  return { 'python3', '-c', 'import sys,time; time.sleep(float(sys.argv[1])); print(sys.argv[2])',
    tostring(delay), vim.json.encode({ groups = groups }) }
end })
local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
local function git(...)
  local args = { 'git', '-C', root }
  vim.list_extend(args, { ... })
  local result = vim.system(args, { text = true }):wait()
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout)
end
local function put(path, value) vim.fn.writefile({ value }, root .. '/' .. path) end
git('init', '--quiet'); git('config', 'user.name', 'Review test'); git('config', 'user.email', 'review@example.invalid')
for _, path in ipairs({ 'a.lua', 'both.lua', 'deleted.lua', 'old.lua' }) do put(path, 'return "base"') end
git('add', '.'); git('commit', '-qm', 'base')
put('both.lua', 'return "staged"'); git('add', 'both.lua')
git('mv', 'old.lua', 'renamed.lua')
put('both.lua', 'return "working"'); put('a.lua', 'return "a-working"')
vim.fn.delete(root .. '/deleted.lua'); put('fresh.lua', 'return "untracked"')
vim.cmd.cd(root)
local view
local function open(args)
  vim.cmd('DiffviewOpen ' .. (args or ''))
  assert(vim.wait(5000, function()
    view = require('diffview.lib').get_current_view()
    return view and view.initialized and view.cur_entry and view.cur_entry.opened
  end), 'working comparison did not initialize')
  route.open()
  assert(view.panel._review_file_order, 'working comparison did not attach')
end
local function press(key) vim.fn.maparg(key, 'n', false, true).callback() end
local function file(kind, path)
  for _, entry in view.files:iter() do if entry.kind == kind and entry.path == path then return entry end end
end
local function select(kind, path)
  route.open(); view.panel:highlight_file(assert(file(kind, path), 'missing ' .. kind .. ':' .. path))
end
local function status(kind, path)
  local line
  view.panel.components[kind].files.comp:deep_some(function(comp)
    if comp.name == 'file' and comp.context.path == path and comp.height > 0 then line = comp.lstart end
  end)
  local ns = api.nvim_get_namespaces()['review-file-status']
  for _, mark in ipairs(api.nvim_buf_get_extmarks(view.panel.bufid, ns, 0, -1, { details = true })) do
    if mark[2] == line then return mark[4].virt_text[1][1] end
  end
end
local function mark(kind, path, key, label)
  select(kind, path); press(key)
  assert(vim.wait(3000, function() return status(kind, path) == label end), 'mark failed: ' .. kind .. ':' .. path)
end
local function order()
  return vim.tbl_map(function(entry) return entry.kind .. ':' .. entry.path end, view.panel:ordered_file_list())
end
local function refresh()
  local done = false
  view:update_files(function(err) assert(not err); done = true end)
  assert(vim.wait(5000, function() return done end))
  route.open()
end
local function ask()
  local count = #notifications
  press('go')
  assert(vim.wait(5000, function() return #notifications > count end), 'assistant did not finish')
end
open()
assert(view.files:len() == 6)
mark('working', 'both.lua', 'md', '[done] ')
mark('staged', 'both.lua', 'ml', '[later] ')
mark('working', 'a.lua', 'md', '[done] ')
assert(status('working', 'both.lua') == '[done] ', 'staged mark changed working mark')
select('working', 'fresh.lua'); press('K'); press('K'); press('K')
select('staged', 'renamed.lua'); press('K')
local custom = order()
press('K'); assert(vim.deep_equal(order(), custom), 'file crossed staging section boundary')
vim.cmd.DiffviewClose(); open()
assert(vim.deep_equal(order(), custom), 'working order was not restored')
assert(vim.wait(3000, function() return status('working', 'both.lua') == '[done] ' end))
assert(status('staged', 'both.lua') == '[later] ')
ask()
local working = assert(prompt:match('ID %d+ | both.lua | section working.-\n(.-)\n\n'))
local staged = assert(prompt:match('ID %d+ | both.lua | section staged.-\n(.-)\n\n'))
assert(working:find('-return "staged"', 1, true) and working:find('+return "working"', 1, true), 'wrong unstaged diff')
assert(staged:find('-return "base"', 1, true) and staged:find('+return "staged"', 1, true), 'wrong staged diff')
assert(prompt:find('+return "untracked"', 1, true), 'untracked content missing')
assert(prompt:find('deleted file mode', 1, true), 'deletion missing')
assert(prompt:find('rename from old.lua', 1, true), 'rename missing')
local shown = {}
for _, kind in ipairs({ 'conflicting', 'working', 'staged' }) do
  for _, comp in ipairs(view.panel.components[kind].files.comp.components) do
    shown[#shown + 1] = comp.context.kind .. ':' .. comp.context.path
  end
end
assert(vim.deep_equal(order(), shown), 'AI navigation order disagrees with section order')
press('gc'); assert(vim.deep_equal(order(), custom), 'AI order replaced custom order')
put('both.lua', 'return "changed"'); refresh()
assert(vim.wait(3000, function() return status('working', 'both.lua') == '[todo] ' end), 'same-stat edit did not invalidate done')
assert(status('staged', 'both.lua') == '[later] ' and status('working', 'a.lua') == '[done] ', 'edit reset unrelated marks')
put('new.lua', 'return "new"'); refresh()
assert(order()[1] == custom[1] and status('working', 'a.lua') == '[done] ', 'new file reset existing order/marks')
assert(status('working', 'new.lua') == '[todo] ')
select('working', 'a.lua'); press('-')
assert(vim.wait(5000, function() return file('staged', 'a.lua') and not file('working', 'a.lua') end), 'native staging broke')
route.open()
assert(status('staged', 'a.lua') == '[todo] ', 'staging inherited another diff\'s completion mark')
assert(status('staged', 'both.lua') == '[later] ', 'index edit reset unrelated staged mark')
select('staged', 'a.lua'); press('-')
assert(vim.wait(5000, function() return file('working', 'a.lua') and not file('staged', 'a.lua') end), 'native unstaging broke')
route.open()
assert(status('working', 'a.lua') == '[todo] ', 'unstaging resurrected a removed completion mark')
-- Reject an AI response if saved content changes while the request is running,
-- even when no Diffview refresh has happened yet.
delay = 0.5
local requested, count, before = requests, #notifications, order()
press('go'); assert(vim.wait(3000, function() return requests > requested end))
put('both.lua', 'return "changed-again"')
assert(vim.wait(5000, function() return #notifications > count end))
assert(notifications[#notifications]:find('Diff changed', 1, true), 'stale AI response accepted')
assert(vim.deep_equal(order(), before), 'stale AI response changed order')
delay = 0
mark('working', 'both.lua', 'md', '[done] ')
-- Resume the actual on-disk state in a separate Neovim process.
local resume_script = vim.fn.tempname() .. '.lua'
vim.fn.writefile(vim.split(([=[
vim.defer_fn(function()
  local ok, err = xpcall(function()
    vim.cmd.DiffviewOpen()
    local lib = require('diffview.lib')
    assert(vim.wait(5000, function()
      local v = lib.get_current_view()
      return v and v.initialized and v.cur_entry and v.cur_entry.opened
    end))
    local panel = lib.get_current_view().panel
    local paths = vim.tbl_map(function(file) return file.kind .. ':' .. file.path end, panel:ordered_file_list())
    assert(vim.deep_equal(paths, vim.json.decode(%q)), 'working order lost across processes')
    local ns = vim.api.nvim_get_namespaces()['review-file-status']
    local labels = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(panel.bufid, ns, 0, -1, { details = true })) do
      labels[mark[2]] = mark[4].virt_text[1][1]
    end
    for kind, expected in pairs({ working = '[done] ', staged = '[later] ' }) do
      local found = false
      panel.components[kind].files.comp:deep_some(function(comp)
        if comp.name == 'file' and comp.context.path == 'both.lua' then
          assert(labels[comp.lstart] == expected, 'working marks lost across processes')
          found = true
        end
      end)
      assert(found)
    end
    vim.cmd.DiffviewClose()
  end, debug.traceback)
  if not ok then print(err); vim.cmd('cquit') end
  vim.cmd('qa!')
end, 100)
]=]):format(vim.json.encode(order())), '\n'), resume_script)
local resumed = vim.system({ vim.v.progpath, '--headless', '-c', 'lua dofile(' .. string.format('%q', resume_script) .. ')' },
  { cwd = root, text = true, timeout = 15000 }):wait()
vim.fn.delete(resume_script)
assert(resumed.code == 0, 'fresh process failed: ' .. (resumed.stderr or '') .. (resumed.stdout or ''))
vim.cmd.DiffviewClose(); put('both.lua', 'return "edited-while-closed"'); open()
assert(vim.wait(3000, function() return status('working', 'both.lua') == '[todo] ' end), 'restart retained stale done mark')
assert(status('staged', 'both.lua') == '[later] ', 'restart lost unchanged staged mark')
press('gd'); press('i'); assert(view.panel.listing_style == 'tree')
press('i'); assert(view.panel.listing_style == 'list')
vim.cmd.DiffviewClose(); open('--cached')
assert(status('working', 'both.lua') == '[todo] ', 'cached comparison reused working-tree marks')
mark('working', 'both.lua', 'md', '[done] ')
ask()
assert(prompt:find('+return "staged"', 1, true) and not prompt:find('edited-while-closed', 1, true), 'cached AI read working content')
vim.cmd.DiffviewClose(); open('--cached')
assert(vim.wait(3000, function() return status('working', 'both.lua') == '[done] ' end), 'cached status did not persist')
vim.cmd.DiffviewClose()
vim.fn.delete(root, 'rf')
print('PASS: working/staged/cached reviews, exact AI diffs, section ordering, native staging, content invalidation, stale AI rejection and persistence.')
vim.cmd('qa!')
