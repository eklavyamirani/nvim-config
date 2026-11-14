-- Coauthor re-anchoring: visual <leader>tr with its picker order, the side
-- split's r with the {edited} suggestion, adjusting the selection, cancelling,
-- and saving unsaved edits before the move.
local api = vim.api
local H = dofile('tests/coauthor_setup.lua')
local coauthor, idle, cli = H.coauthor, H.idle, H.cli

local function keys(text) api.nvim_feedkeys(api.nvim_replace_termcodes(text, true, false, true), 'x', false) end

-- Answers the next picker with the item whose text starts with `prefix` (nil cancels).
local offered
local function choose(prefix)
  vim.ui.select = function(items, opts, on_choice)
    offered = vim.tbl_map(opts.format_item, items)
    for _, item in ipairs(items) do
      if prefix and opts.format_item(item):find(prefix, 1, true) == 1 then return on_choice(item) end
    end
    on_choice(nil)
  end
end

local path = H.doc('notes.md', {
  '# Notes', 'keep', 'same', 'gone soon', 'Moved text.', 'filler', 'same', 'End.',
})
cli('comment', path, '--lines', '2-2', 'anchored')
cli('comment', path, '--lines', '3-3', 'drifts')
cli('comment', path, '--lines', '4-4', 'orphan one')
cli('comment', path, '--lines', '8-8', 'orphan two')
cli('reply', path, 't4', '--edited', '6-7', 'Rewrote the ending.')
-- The agent rewrote lines 4 and 8 and inserted a line above "same".
vim.fn.writefile({ '# Notes', 'keep', 'new', 'same', 'Moved text.', 'Ending, rewritten.', 'More ending.', 'same' }, path)
cli('done', path)
vim.cmd.edit(path)
local buf = api.nvim_get_current_buf()
idle()
assert(#coauthor.orphans(buf) == 2, vim.inspect(coauthor.orphans(buf)))

-- 1. Picker order: orphaned, then drifted, then the rest.
local texts = vim.tbl_map(function(item) return item.text end, coauthor.reanchor_candidates(buf))
assert(#texts == 4, vim.inspect(texts))
assert(texts[1]:find('^t3 · orphaned · was line 4: gone soon') and texts[2]:find('^t4 · orphaned · was line 8: End%.'),
  vim.inspect(texts))
assert(texts[3]:find('^t2 · drifted · lines 4%-4: same') and texts[4]:find('^t1 · awaiting ai · lines 2%-2: keep'),
  vim.inspect(texts))

-- 2. Visual <leader>tr anchors the chosen thread to the selection, saved at once.
choose('t3 ')
vim.cmd('normal! 5GV')
vim.fn.maparg('<leader>tr', 'x', false, true).callback()
idle()
assert(api.nvim_get_mode().mode == 'n')
assert(offered[1]:find('^t3'), vim.inspect(offered))
local t3 = H.thread(cli('list', path), 't3')
assert(vim.deep_equal(t3.stored, { 5, 5 }) and t3.anchor[1] == 'Moved text.', vim.inspect(t3))
assert(vim.deep_equal(t3.was, { 'gone soon' }), 'the old anchor text is kept as was:')
assert(H.marks(buf).t3 and H.marks(buf).t3.first == 5)

-- A cancelled picker changes nothing.
choose(nil)
vim.cmd('normal! 2GV')
vim.fn.maparg('<leader>tr', 'x', false, true).callback()
idle()
assert(vim.deep_equal(H.thread(cli('list', path), 't1').stored, { 2, 2 }))

-- 3. The side split's r selects the {edited} range of the last AI reply; <CR> confirms.
local doc_win = api.nvim_get_current_win()
api.nvim_win_set_cursor(doc_win, { 1, 0 })
coauthor.open_split()
local split_buf = vim.fn.bufnr('coauthor://threads')
local split_win = vim.fn.bufwinid(split_buf)
local function split_row(pattern)
  for row, line in ipairs(api.nvim_buf_get_lines(split_buf, 0, -1, false)) do
    if line:find(pattern) then return row end
  end
end
api.nvim_set_current_win(split_win)
api.nvim_win_set_cursor(split_win, { split_row('^%- t4 '), 0 })
keys('r')
assert(api.nvim_get_current_win() == doc_win, 'r did not jump to the document')
local mode = api.nvim_get_mode().mode
assert(mode == 'V', 'expected a line selection, got ' .. mode)
assert(vim.fn.getpos('v')[2] == 6 and vim.fn.line('.') == 7, 'suggestion is not the {edited 6-7} range')
-- Nothing has moved yet.
assert(vim.deep_equal(H.thread(cli('list', path), 't4').stored, { 8, 8 }))
keys('<CR>')
idle()
local t4 = H.thread(cli('list', path), 't4')
assert(vim.deep_equal(t4.stored, { 6, 7 }) and t4.anchor[2] == 'More ending.', vim.inspect(t4))
assert(#coauthor.orphans(buf) == 0)
assert(vim.fn.maparg('<CR>', 'x') == '', 'the confirm mapping outlived the re-anchor')

-- 4. Without an {edited} reply, r suggests the current lines; the user can
-- adjust the selection before confirming. Unsaved edits are written first.
api.nvim_buf_set_lines(buf, 0, 0, false, { 'Unsaved first line.' })
api.nvim_win_set_cursor(doc_win, { 3, 0 })
api.nvim_exec_autocmds('CursorMoved', { buffer = buf })
api.nvim_set_current_win(split_win)
api.nvim_win_set_cursor(split_win, { split_row('^## t1 '), 0 })
keys('r')
assert(api.nvim_get_mode().mode == 'V' and vim.fn.getpos('v')[2] == 3 and vim.fn.line('.') == 3)
keys('j<CR>')
idle()
assert(not vim.bo[buf].modified and vim.fn.readfile(path)[1] == 'Unsaved first line.', 'not saved before the move')
local t1 = H.thread(cli('list', path), 't1')
assert(vim.deep_equal(t1.stored, { 3, 4 }) and vim.deep_equal(t1.anchor, { 'keep', 'new' }), vim.inspect(t1))
assert(H.marks(buf).t1.first == 3 and H.marks(buf).t1.last == 4, vim.inspect(H.marks(buf)))

-- 5. Leaving Visual mode cancels.
api.nvim_win_set_cursor(doc_win, { 5, 0 })
api.nvim_exec_autocmds('CursorMoved', { buffer = buf })
api.nvim_set_current_win(split_win)
api.nvim_win_set_cursor(split_win, { split_row('^## t2 '), 0 })
keys('r')
assert(api.nvim_get_mode().mode == 'V')
keys('<Esc>')
idle()
assert(vim.deep_equal(H.thread(cli('list', path), 't2').stored, { 5, 5 }))
assert(vim.fn.maparg('<CR>', 'x') == '', 'cancel left the confirm mapping')
local cancelled = false
for _, n in ipairs(H.notices) do cancelled = cancelled or n.message:find('re-anchor cancelled', 1, true) ~= nil end
assert(cancelled)

H.finish('PASS: coauthor re-anchoring from a selection and the side split, {edited} suggestion, adjusting, cancelling and saving first.')
