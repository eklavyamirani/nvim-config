-- Coauthor views: side split (with and without orphans), its keys, the float,
-- quickfix ordering, the statusline text and resolving from the document.
local api = vim.api
local H = dofile('tests/coauthor_setup.lua')
local coauthor, idle, cli = H.coauthor, H.idle, H.cli

local path = H.doc('plan.md', {
  '# Plan', '', 'Intro line.', '', 'Second point.', 'Second point, continued.', 'Doomed line.', 'End.',
})
cli('comment', path, '--lines', '3-3', 'expand the intro')
cli('comment', path, '--lines', '5-6', 'merge these')
cli('reply', path, 't2', '--edited', '5-6', 'Merged.\nSee the new wording.')
cli('comment', path, '--lines', '7-7', 'remove this?')
-- The agent rewrote line 7 away: t3 is an orphan at its last-known line.
vim.fn.writefile({ '# Plan', '', 'Intro line.', '', 'Second point.', 'Second point, continued.', 'Replaced.', 'End.' }, path)

vim.cmd.edit(path)
local buf = api.nvim_get_current_buf()
idle()
assert(H.marks(buf).t1 and H.marks(buf).t2 and not H.marks(buf).t3, vim.inspect(H.marks(buf)))

-- Rendering with an orphan: pinned Needs anchor section, then the cursor's thread.
local lines, ids = coauthor.render(buf, 5)
local text = table.concat(lines, '\n')
assert(text:find('^# Needs anchor\n\n%- t3 · was line 7 · awaiting ai\n  was: Doomed line%.\n'), text)
assert(text:find('## t2 · lines 5-6 · awaiting me\n> Second point.\n> Second point, continued.\n\n'
  .. '**me:** merge these\n\n**ai:** {edited 5-6} Merged.\nSee the new wording.', 1, true), text)
assert(ids[3] == 't3' and ids[#lines] == 't2', vim.inspect(ids))
lines = coauthor.render(buf, 1)
assert(lines[#lines]:find('No thread on this line'), vim.inspect(lines))

-- Statusline counts, zero parts left out.
assert(coauthor.statusline() == 'awaiting me 1 · awaiting ai 1 · orphan 1', coauthor.statusline())

-- Quickfix: orphans first at their last-known line, then by position.
local items = coauthor.quickfix_items(buf)
assert(#items == 3, vim.inspect(items))
assert(items[1].text == '[orphan] t3 · was line 7: Doomed line.' and items[1].lnum == 7, vim.inspect(items[1]))
assert(items[2].text == 't1 · awaiting ai · me: expand the intro' and items[2].lnum == 3, vim.inspect(items[2]))
assert(items[3].text == 't2 · awaiting me · ai: {edited 5-6} Merged.' and items[3].lnum == 5, vim.inspect(items[3]))
api.nvim_win_set_cursor(0, { 1, 0 })
coauthor.quickfix()
local qf = vim.fn.getqflist({ title = 1, items = 1 })
assert(qf.title == 'Coauthor threads' and #qf.items == 3 and qf.items[1].text:find('^%[orphan%]'), vim.inspect(qf))
vim.cmd('cclose')

-- Side split follows the cursor's thread.
local doc_win = api.nvim_get_current_win()
api.nvim_win_set_cursor(doc_win, { 3, 0 })
coauthor.open_split()
assert(api.nvim_get_current_win() == doc_win, 'focus should stay in the document')
local split_buf = vim.fn.bufnr('coauthor://threads')
local split_win = vim.fn.bufwinid(split_buf)
assert(split_win ~= -1, 'side split did not open')
assert(H.buffer_text(split_buf):find('## t1 · lines 3-3 · awaiting ai', 1, true), H.buffer_text(split_buf))
api.nvim_win_set_cursor(doc_win, { 6, 0 })
vim.api.nvim_exec_autocmds('CursorMoved', { buffer = buf })
assert(H.buffer_text(split_buf):find('## t2 · lines 5-6', 1, true), H.buffer_text(split_buf))

-- <CR> on the orphan entry jumps to its last-known line; x resolves it.
api.nvim_set_current_win(split_win)
api.nvim_win_set_cursor(split_win, { 3, 0 })
vim.cmd('normal \r')
assert(api.nvim_get_current_win() == doc_win and api.nvim_win_get_cursor(doc_win)[1] == 7)
api.nvim_set_current_win(split_win)
api.nvim_win_set_cursor(split_win, { 3, 0 })
vim.cmd('normal x')
idle()
assert(H.thread(cli('list', path), 't3').status == 'resolved')
-- Rendering without orphans.
assert(not H.buffer_text(split_buf):find('Needs anchor', 1, true), H.buffer_text(split_buf))
assert(coauthor.statusline() == '', 'the split itself is not a coauthor document')

-- <CR> on a thread jumps to its anchor.
api.nvim_set_current_win(doc_win)
assert(coauthor.statusline() == 'awaiting me 1 · awaiting ai 1', coauthor.statusline())
api.nvim_win_set_cursor(doc_win, { 5, 0 })
api.nvim_exec_autocmds('CursorMoved', { buffer = buf })
api.nvim_win_set_cursor(doc_win, { 1, 0 })
local t2_row
for row, line in ipairs(api.nvim_buf_get_lines(split_buf, 0, -1, false)) do
  if line:find('^## t2') then t2_row = row end
end
api.nvim_set_current_win(split_win)
api.nvim_win_set_cursor(split_win, { t2_row, 0 })
vim.cmd('normal \r')
assert(api.nvim_win_get_cursor(doc_win)[1] == 5)

-- The float shows the thread under the cursor and closes when the cursor moves.
api.nvim_win_set_cursor(doc_win, { 3, 0 })
local float = coauthor.open_float()
assert(float and api.nvim_win_get_config(float).relative ~= '', 'not a floating window')
assert(H.buffer_text(api.nvim_win_get_buf(float)):find('## t1 · lines 3-3', 1, true))
api.nvim_win_set_cursor(doc_win, { 4, 0 })
api.nvim_exec_autocmds('CursorMoved', { buffer = buf })
assert(not api.nvim_win_is_valid(float), 'float stayed open')

-- <leader>tx resolves the thread under the cursor from the document.
api.nvim_win_set_cursor(doc_win, { 3, 0 })
vim.fn.maparg('<leader>tx', 'n', false, true).callback()
idle()
assert(H.thread(cli('list', path), 't1').status == 'resolved')
assert(H.marks(buf).t1 == nil)
assert(coauthor.statusline() == 'awaiting me 1', coauthor.statusline())

-- a accepts a drift: the anchor stays where it is and loses the drifted flag.
local drift = H.doc('drift.md', { 'a', 'same', 'b' })
cli('comment', drift, '--lines', '2-2', 'x')
vim.fn.writefile({ 'same', 'c', 'c', 'c', 'same' }, drift)
cli('done', drift)
vim.cmd.edit(drift)
local drift_buf = api.nvim_get_current_buf()
idle()
assert(H.marks(drift_buf).t1.first == 1)
api.nvim_win_set_cursor(0, { 1, 0 })
api.nvim_exec_autocmds('CursorMoved', { buffer = drift_buf })
assert(H.buffer_text(split_buf):find('## t1 · lines 1-1 · awaiting ai · drifted', 1, true), H.buffer_text(split_buf))
api.nvim_set_current_win(split_win)
local drift_row
for row, line in ipairs(api.nvim_buf_get_lines(split_buf, 0, -1, false)) do
  if line:find('^## t1') then drift_row = row end
end
api.nvim_win_set_cursor(split_win, { drift_row, 0 })
vim.cmd('normal a')
idle()
local accepted = H.thread(cli('list', drift), 't1')
assert(accepted.state == 'anchored' and accepted.stored[1] == 1, vim.inspect(accepted))
assert(not H.buffer_text(split_buf):find('drifted', 1, true), H.buffer_text(split_buf))

H.finish('PASS: coauthor side split with and without orphans, its keys, float, quickfix order, statusline and resolve.')
