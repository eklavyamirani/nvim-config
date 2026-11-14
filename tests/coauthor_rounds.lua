-- Coauthor rounds: submit (save, sync, open, baseline, lock, prompt), an agent
-- writing the document and threads file mid-round (no reload until done, live
-- thread refresh, lock holds), the three ways a round ends, watching through
-- rename-based saves, and the review diff.
local api = vim.api
local H = dofile('tests/coauthor_setup.lua')
local coauthor, idle, cli = H.coauthor, H.idle, H.cli

local copied = {}
vim.g.clipboard = {
  name = 'test clipboard',
  copy = { ['+'] = function(lines) copied = lines end, ['*'] = function(lines) copied = lines end },
  paste = { ['+'] = function() return copied end, ['*'] = function() return copied end },
}

local function wait(condition, message)
  assert(vim.wait(15000, function() return coauthor.idle() and condition() end, 20), message)
end

-- Writes like an agent's edit tool: a temp file renamed over the document.
local function agent_write(path, lines)
  local temp = path .. '.agent-tmp'
  vim.fn.writefile(lines, temp)
  assert(vim.uv.fs_rename(temp, path))
end

local function notice(pattern)
  for i = #H.notices, 1, -1 do
    if H.notices[i].message:find(pattern) then return H.notices[i].message end
  end
end

local original = { '# Rollout', '', 'The rollout takes two weeks.', 'We start Monday.', 'Risky bit.', 'End.' }
local path = H.doc('rollout.md', original)
vim.cmd.edit(path)
local buf = api.nvim_get_current_buf()
idle()

-- Nothing awaiting ai: submit refuses.
coauthor.submit()
assert(notice('no threads are awaiting ai'), vim.inspect(H.notices))

H.answer('give phases')
api.nvim_win_set_cursor(0, { 3, 0 })
coauthor.comment('line')
H.answer('remove this?')
api.nvim_win_set_cursor(0, { 5, 0 })
coauthor.comment('line')
idle()

-- 1. Submit saves unsaved edits, syncs, opens the round, saves the baseline,
-- locks the buffer and yanks the prompt.
api.nvim_buf_set_lines(buf, 1, 1, false, { 'Unsaved intro.' })
assert(vim.bo[buf].modified)
coauthor.submit()
wait(function() return coauthor.docs[buf].round ~= nil end, 'round did not open')
assert(not vim.bo[buf].modified and vim.fn.readfile(path)[2] == 'Unsaved intro.', 'submit did not save')
local state = cli('list', path)
assert(state.round == 'open', state.round)
assert(vim.deep_equal(H.thread(state, 't1').stored, { 4, 4 }), 'anchors were not synced before submit')
-- Any spelling of the path finds the baseline (8.3 names, /var -> /private/var).
local baseline = coauthor.baseline_path(path)
assert(baseline == coauthor.baseline_path(api.nvim_buf_get_name(buf)))
assert(vim.deep_equal(vim.fn.readfile(baseline), vim.fn.readfile(path)), 'baseline differs from the saved document')
assert(not vim.bo[buf].modifiable and vim.bo[buf].readonly, 'buffer not locked')
local prompt = table.concat(copied, '\n')
assert(prompt == coauthor.prompt(api.nvim_buf_get_name(buf)), prompt)
assert(prompt:find('coauthor list ', 1, true) and prompt:find('@', 1, true), prompt)
assert(notice('round open'), vim.inspect(H.notices))

-- The lock blocks edits and a plain :w.
assert(not pcall(api.nvim_buf_set_lines, buf, 0, 1, false, { 'edit' }), 'nomodifiable did not hold')
local wrote = pcall(vim.cmd, 'write')
assert(not wrote, ':w of a locked buffer succeeded')
-- A second submit is refused while the round is open.
coauthor.submit()
assert(notice('already open'))

-- 2. Mid-round, the agent edits the document and replies: replies show up live,
-- the buffer is not reloaded and the marks stay.
local edited = { '# Rollout', 'Unsaved intro.', '', 'Phase 1: a week.', 'Phase 2: a week.', 'We start Monday.', 'End.' }
agent_write(path, edited)
cli('reply', path, 't1', '--edited', '4-5', 'Split into phases.')
wait(function()
  local thread = coauthor.docs[buf].by_id.t1
  return thread and thread.status == 'awaiting_me'
end, 'agent reply did not refresh the threads')
vim.cmd('silent! checktime')
assert(api.nvim_buf_get_lines(buf, 2, 3, false)[1] == '', 'buffer reloaded mid-round')
assert(api.nvim_buf_get_lines(buf, 3, 4, false)[1] == 'The rollout takes two weeks.', 'buffer reloaded mid-round')
assert(H.marks(buf).t1.first == 4 and H.marks(buf).t1.hl == 'CoauthorAwaitingMe', vim.inspect(H.marks(buf)))
assert(vim.bo[buf].readonly)
-- Comments from Neovim still go straight through mid-round.
H.answer('and the date?')
api.nvim_win_set_cursor(0, { 6, 0 })
coauthor.comment('line')
idle()
assert(#H.thread(cli('list', path), 't2').messages == 2)

-- 3. `coauthor done` from the agent ends the round: unlock, reload, saved anchors, one notice.
cli('reply', path, 't2', '--no-edit', 'Kept; it matters.')
cli('done', path)
wait(function() return coauthor.docs[buf].round == nil and not vim.bo[buf].readonly end, 'round did not end on done')
wait(function() return api.nvim_buf_get_lines(buf, 3, 4, false)[1] == 'Phase 1: a week.' end, 'not reloaded')
assert(vim.bo[buf].modifiable)
local marks = H.marks(buf)
assert(marks.t1 == nil and marks.t2 == nil, 'both anchors are gone from the new text: ' .. vim.inspect(marks))
local message = notice('round done')
assert(message and message:find('2 replies · 1 edit · 2 orphaned', 1, true), message)
-- The reload is one undo step.
vim.cmd('silent undo')
assert(api.nvim_buf_get_lines(buf, 3, 4, false)[1] == 'The rollout takes two weeks.', 'reload is not undoable')
vim.cmd('silent redo')

-- 4. The review diff compares with the baseline taken at submit.
local doc_win = api.nvim_get_current_win()
coauthor.diff()
local diff_win = coauthor.docs[buf].diff_win
assert(diff_win and api.nvim_win_is_valid(diff_win), 'diff window missing')
assert(vim.wo[diff_win].diff and vim.wo[doc_win].diff, 'diff mode not on')
assert(vim.deep_equal(api.nvim_buf_get_lines(api.nvim_win_get_buf(diff_win), 0, -1, false), vim.fn.readfile(baseline)))
assert(api.nvim_get_current_win() == doc_win)
coauthor.diff()
assert(not api.nvim_win_is_valid(diff_win) and not vim.wo[doc_win].diff, 'diff did not close')

-- 5. :CoauthorDone when the agent forgets `coauthor done`.
H.answer('shorter?')
api.nvim_win_set_cursor(0, { 4, 0 })
coauthor.comment('line')
idle()
coauthor.submit()
wait(function() return coauthor.docs[buf].round ~= nil end, 'second round did not open')
local before_done = vim.fn.readfile(path)
before_done[4] = 'Phase 1: five days.'
agent_write(path, before_done)
cli('reply', path, 't3', '--edited', '4', 'Shortened.')
vim.cmd('CoauthorDone')
wait(function() return coauthor.docs[buf].round == nil end, ':CoauthorDone did not end the round')
wait(function() return api.nvim_buf_get_lines(buf, 3, 4, false)[1] == 'Phase 1: five days.' end, 'not reloaded')
assert(cli('list', path).round == 'done')
assert(notice('1 reply · 1 edit'), vim.inspect(H.notices))

-- 6. :CoauthorCancel ends without waiting and without `coauthor done`.
H.answer('one more')
api.nvim_win_set_cursor(0, { 7, 0 })
coauthor.comment('line')
idle()
coauthor.submit()
wait(function() return coauthor.docs[buf].round ~= nil end, 'third round did not open')
vim.cmd('CoauthorCancel')
assert(coauthor.docs[buf].round == nil and vim.bo[buf].modifiable and not vim.bo[buf].readonly)
idle()
assert(cli('list', path).round == 'open', 'cancel must not run coauthor done')
assert(notice('round cancelled'), vim.inspect(H.notices))

-- 7. Outside a round, watching survives rename-based saves on both sides.
vim.o.backupcopy = 'auto'
api.nvim_buf_set_lines(buf, 0, 1, false, { '# Rollout v2' })
vim.cmd('silent write')
idle()
for n = 1, 2 do
  local lines = vim.fn.readfile(path)
  lines[1] = '# Rollout v' .. (2 + n)
  agent_write(path, lines)
  wait(function() return api.nvim_buf_get_lines(buf, 0, 1, false)[1] == '# Rollout v' .. (2 + n) end,
    'external save ' .. n .. ' was not picked up')
end
-- The threads file is watched too: an outside reply appears without a refresh.
cli('reply', path, 't4', '--no-edit', 'Noted.')
wait(function() return coauthor.docs[buf].by_id.t4.status == 'awaiting_me' end, 'threads change was missed')

H.finish('PASS: coauthor submit, lock, mid-round agent writes, done/:CoauthorDone/:CoauthorCancel, rename-safe watching and review diff.')
