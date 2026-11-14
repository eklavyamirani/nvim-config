-- Coauthor client: commenting, replies, anchored-line marking, sync on :w,
-- navigation, auto-enable and the missing-binary fallback. Drives the real CLI
-- built by `cargo test` (the coauthor suite runs that first).
local api = vim.api
local windows = vim.fn.has('win32') == 1
local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)
vim.g.mapleader = ' '
vim.cmd('filetype on')
local temp = vim.fn.tempname()
vim.fn.mkdir(temp .. '/state', 'p')
vim.fn.mkdir(temp .. '/docs', 'p')
-- The CLI reads these from the environment Neovim passes on.
vim.env.XDG_STATE_HOME = temp .. '/state'
vim.env.LOCALAPPDATA = temp .. '/state'
local binary = root .. '/coauthor/target/debug/coauthor' .. (windows and '.exe' or '')
assert(vim.fn.executable(binary) == 1, 'build the CLI first (cargo test): ' .. binary)

local notices = {}
local original_notify = vim.notify
vim.notify = function(message, level)
  table.insert(notices, { message = message, level = level })
end

local coauthor = require('config.coauthor')
coauthor.setup()

local function idle()
  assert(vim.wait(10000, coauthor.idle, 10), 'coauthor CLI calls did not finish')
end

-- Answers the next vim.ui.input prompt.
local prompts = {}
local function answer(text)
  vim.ui.input = function(opts, on_confirm)
    table.insert(prompts, opts.prompt)
    on_confirm(text)
  end
end

local function cli(...)
  local result = vim.system({ binary, '--json', ... }, { text = true }):wait()
  assert(result.code == 0, result.stderr)
  return vim.json.decode(result.stdout)
end

local function marks(buf)
  local found = {}
  for _, mark in ipairs(api.nvim_buf_get_extmarks(buf, api.nvim_create_namespace('coauthor'), 0, -1, { details = true })) do
    local details = mark[4]
    if details.virt_text then
      found[details.virt_text[1][1]] = {
        first = mark[2] + 1, last = details.end_row + 1, hl = details.number_hl_group,
        id_hl = details.virt_text[1][2],
      }
    end
  end
  return found
end

local function write(path, lines) vim.fn.writefile(lines, path) end

-- 1. Missing binary: one notice, no errors, nothing enabled.
vim.g.coauthor_command = 'coauthor-missing-' .. vim.fn.rand()
local missing_doc = temp .. '/docs/missing.md'
write(missing_doc, { '# Missing' })
vim.cmd.edit(missing_doc)
answer('a comment')
coauthor.comment('line')
vim.cmd('Coauthor')
coauthor.comment('line')
idle()
local warnings = vim.tbl_filter(function(n) return n.message:find('was not found', 1, true) end, notices)
assert(#warnings == 1, 'expected one missing-binary notice, got ' .. vim.inspect(notices))
assert(not coauthor.enabled(0), 'enabled without a binary')
vim.cmd('bwipeout!')

-- 2. Markdown auto-enables; a comment anchors to the buffer's lines.
vim.g.coauthor_command = binary
notices = {}
local doc_path = temp .. '/docs/rollout.md'
write(doc_path, { '# Rollout', '', 'The rollout takes two weeks.', 'We start Monday.', 'Ship it.', 'Done.' })
vim.cmd.edit(doc_path)
local buf = api.nvim_get_current_buf()
idle()
assert(coauthor.enabled(buf), 'markdown was not auto-enabled')
api.nvim_win_set_cursor(0, { 3, 0 })
answer('too vague, give phases')
coauthor.comment('line')
idle()
assert(prompts[#prompts] == 'Comment on lines 3-3: ', prompts[#prompts])
local state = cli('list', doc_path)
assert(#state.threads == 1 and state.threads[1].id == 't1', vim.inspect(state))
assert(state.threads[1].messages[1].text == 'too vague, give phases')
local m = marks(buf)
assert(m.t1 and m.t1.first == 3 and m.t1.last == 3, vim.inspect(m))
assert(m.t1.hl == 'CoauthorAwaitingAi', 'awaiting ai should be blue: ' .. tostring(m.t1.hl))
assert(m.t1.id_hl == 'CoauthorId')

-- 3. Inside an anchor, <leader>tc replies to that thread.
answer('why two?')
coauthor.comment('line')
idle()
assert(prompts[#prompts] == 'Reply to t1: ', prompts[#prompts])
state = cli('list', doc_path)
assert(#state.threads == 1 and #state.threads[1].messages == 2, vim.inspect(state.threads))
assert(state.threads[1].messages[2].author == 'me')

-- 4. An agent reply turns the line number peach after a refresh.
cli('reply', doc_path, 't1', '--no-edit', 'Because.')
coauthor.refresh(buf)
idle()
assert(marks(buf).t1.hl == 'CoauthorAwaitingMe', vim.inspect(marks(buf)))

-- 5. A selection with unsaved edits: the anchor text comes from the buffer.
api.nvim_buf_set_lines(buf, 4, 5, false, { 'Ship it on Friday.' })
vim.cmd('normal! 4GVj')
answer('which Monday?')
coauthor.comment('visual')
idle()
assert(api.nvim_get_mode().mode == 'n', 'still in visual mode')
state = cli('list', doc_path)
local t2 = state.threads[2]
assert(t2 and t2.id == 't2', vim.inspect(state.threads))
assert(vim.deep_equal(t2.anchor, { 'We start Monday.', 'Ship it on Friday.' }), vim.inspect(t2.anchor))
m = marks(buf)
assert(m.t2.first == 4 and m.t2.last == 5, vim.inspect(m))

-- 6. Lines inserted above move the extmarks; :w syncs them to the CLI.
api.nvim_buf_set_lines(buf, 1, 1, false, { 'Inserted one.', 'Inserted two.' })
m = marks(buf)
assert(m.t1.first == 5 and m.t2.first == 6 and m.t2.last == 7, vim.inspect(m))
vim.cmd('silent write')
idle()
state = cli('list', doc_path)
assert(vim.deep_equal(state.threads[1].stored, { 5, 5 }), vim.inspect(state.threads[1]))
assert(vim.deep_equal(state.threads[2].stored, { 6, 7 }), vim.inspect(state.threads[2]))
assert(state.threads[2].anchor[2] == 'Ship it on Friday.')
assert(state.threads[1].state == 'anchored' and state.threads[2].state == 'anchored')

-- 7. ]t / [t move between anchors and wrap.
api.nvim_win_set_cursor(0, { 1, 0 })
coauthor.jump(1)
assert(api.nvim_win_get_cursor(0)[1] == 5)
coauthor.jump(1)
assert(api.nvim_win_get_cursor(0)[1] == 6)
coauthor.jump(1)
assert(api.nvim_win_get_cursor(0)[1] == 5, 'did not wrap')
coauthor.jump(-1)
assert(api.nvim_win_get_cursor(0)[1] == 6, 'did not wrap backwards')

-- 8. Resolved threads lose their marks; :Coauthor toggles the buffer.
cli('resolve', doc_path, 't1')
coauthor.refresh(buf)
idle()
assert(marks(buf).t1 == nil and marks(buf).t2 ~= nil, vim.inspect(marks(buf)))
vim.cmd('Coauthor')
assert(not coauthor.enabled(buf) and next(marks(buf)) == nil)
vim.cmd('Coauthor')
idle()
assert(coauthor.enabled(buf) and marks(buf).t2.first == 6, vim.inspect(marks(buf)))

-- 9. Other filetypes: enabled only when they already have threads.
local plain = temp .. '/docs/notes.txt'
write(plain, { 'alpha', 'beta' })
vim.cmd.edit(plain)
idle()
assert(not coauthor.enabled(0), 'a .txt without threads was enabled')
-- Without coauthor, ]t is :tnext again; with no tags that is a message, not an error.
coauthor.jump(1)
vim.cmd('bwipeout')
cli('comment', plain, '--lines', '2-2', 'about beta')
vim.cmd.edit(plain)
idle()
assert(coauthor.enabled(0), 'a file with threads was not auto-enabled')
assert(marks(0).t1 and marks(0).t1.first == 2)

-- 10. A comment whose prompt is cancelled leaves nothing behind.
vim.cmd.edit(doc_path)
api.nvim_win_set_cursor(0, { 1, 0 })
answer(nil)
coauthor.comment('line')
idle()
assert(#cli('list', doc_path).threads == 2)
assert(#api.nvim_buf_get_extmarks(0, api.nvim_create_namespace('coauthor'), 0, -1, {}) == 1)

vim.notify = original_notify
local errors = vim.tbl_filter(function(n) return n.level == vim.log.levels.ERROR end, notices)
assert(#errors == 0, vim.inspect(errors))
print('PASS: coauthor comments, replies, buffer anchor text, line-number marks, sync on :w, ]t/[t, toggle, auto-enable and missing binary.')
vim.cmd('qa!')
