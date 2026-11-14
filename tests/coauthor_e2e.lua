-- End to end, through the real coauthor binary: comment, submit (document
-- lock), a stub agent running list / file edit / move / reply --edited and
-- --no-edit / done, round end, an orphan re-anchored from the side split, the
-- review diff, a user reply, and the next round.
local api = vim.api
local H = dofile('tests/coauthor_setup.lua')
local coauthor, cli = H.coauthor, H.cli

local stub = H.root .. '/tests/coauthor_stub_agent.lua'
local mode = 'e2e'
coauthor.options.agent_command = function(_, ctx)
  return { vim.v.progpath, '-l', stub, mode, ctx.relative, H.binary }
end

local function keys(text) api.nvim_feedkeys(api.nvim_replace_termcodes(text, true, false, true), 'x', false) end
local function wait(condition, message)
  assert(vim.wait(20000, function() return coauthor.idle() and condition() end, 20), message)
end
local function notice(text)
  for i = #H.notices, 1, -1 do
    if H.notices[i].message:find(text, 1, true) then return H.notices[i].message end
  end
end

local original = { '# Launch plan', '', 'Timeline: two weeks.', 'Owner: TBD.', 'Budget line.', 'End.' }
local path = H.doc('launch.md', original)
vim.cmd.edit(path)
local buf = api.nvim_get_current_buf()
local doc_win = api.nvim_get_current_win()
H.idle()

-- Comment on three lines.
for line, text in pairs({ [3] = 'too vague, give phases', [4] = 'who owns this?', [5] = 'is this right?' }) do
  H.answer(text)
  api.nvim_win_set_cursor(doc_win, { line, 0 })
  coauthor.comment('line')
  H.idle()
end
assert(coauthor.statusline() == 'awaiting ai 3', coauthor.statusline())

-- Submit: the document locks while the agent works.
coauthor.submit_headless()
wait(function() return coauthor.docs[buf].round and coauthor.docs[buf].round.job end, 'agent did not start')
assert(not vim.bo[buf].modifiable and vim.bo[buf].readonly, 'document not locked during the round')
assert(not pcall(vim.cmd, 'write'), ':w succeeded on a locked document')
assert(cli('list', path).round == 'open')
vim.fn.writefile({}, path .. '.go')

-- Round end: reloaded, anchors from `coauthor done`, one summary.
wait(function() return coauthor.docs[buf].round == nil and vim.bo[buf].modifiable end, 'round did not end')
wait(function() return api.nvim_buf_get_lines(buf, 3, 4, false)[1]:find('^Timeline: phase 1') ~= nil end, 'not reloaded')
local summary = notice('round done')
assert(summary and summary:find('3 replies · 2 edits · 1 orphaned', 1, true), summary)
local marks = H.marks(buf)
assert(marks.t1.first == 4 and marks.t3.first == 5 and marks.t2 == nil, vim.inspect(marks))
assert(marks.t1.hl == 'CoauthorAwaitingMe')
local state = cli('list', path)
assert(state.round == 'done')
assert(vim.deep_equal(H.thread(state, 't1').was, { 'Timeline: two weeks.' }), 'move kept no was:')
assert(H.thread(state, 't2').state == 'orphaned')
assert(coauthor.statusline() == 'awaiting me 2 · orphan 1', coauthor.statusline())

-- The orphan: the side split pins it; r suggests the agent's {edited 6}; <CR> re-anchors.
api.nvim_win_set_cursor(doc_win, { 1, 0 })
coauthor.open_split()
local split_buf = vim.fn.bufnr('coauthor://threads')
local split_win = vim.fn.bufwinid(split_buf)
local text = H.buffer_text(split_buf)
assert(text:find('# Needs anchor\n\n- t2 · was line 4 · awaiting me\n  was: Owner: TBD.', 1, true), text)
api.nvim_set_current_win(split_win)
api.nvim_win_set_cursor(split_win, { 3, 0 })
keys('r')
assert(api.nvim_get_mode().mode == 'V' and vim.fn.line('.') == 6, 'suggestion is not the {edited 6} line')
keys('<CR>')
H.idle()
local t2 = H.thread(cli('list', path), 't2')
assert(vim.deep_equal(t2.stored, { 6, 6 }) and t2.anchor[1] == 'Owner: platform team.', vim.inspect(t2))
assert(vim.deep_equal(t2.was, { 'Owner: TBD.' }))
assert(#coauthor.orphans(buf) == 0 and coauthor.statusline() == 'awaiting me 3', coauthor.statusline())

-- The review diff shows the document against the copy taken at submit.
coauthor.diff()
local diff_win = coauthor.docs[buf].diff_win
assert(vim.wo[diff_win].diff and vim.wo[doc_win].diff)
assert(vim.deep_equal(api.nvim_buf_get_lines(api.nvim_win_get_buf(diff_win), 0, -1, false), original))
coauthor.diff()

-- Reply in t1 and resolve t3, then the next round.
H.answer('why two phases?')
api.nvim_win_set_cursor(doc_win, { 4, 0 })
coauthor.comment('line')
H.idle()
api.nvim_win_set_cursor(doc_win, { 5, 0 })
vim.fn.maparg('<leader>tx', 'n', false, true).callback()
H.idle()
assert(coauthor.statusline() == 'awaiting me 1 · awaiting ai 1', coauthor.statusline())
mode = 'done'
coauthor.submit_headless()
wait(function() return coauthor.docs[buf].round == nil and vim.bo[buf].modifiable end, 'second round did not end')
wait(function() return api.nvim_buf_get_lines(buf, 4, 5, false)[1] == 'Added by the agent.' end, 'not reloaded')
local t1 = H.thread(cli('list', path), 't1')
assert(t1.status == 'awaiting_me' and #t1.messages == 4, vim.inspect(t1))
assert(t1.messages[4].text == '{edited 5} Added a line.', t1.messages[4].text)
assert(notice('round done · 1 reply · 1 edit · 0 orphaned'), vim.inspect(H.notices))
assert(H.marks(buf).t1.first == 4 and H.marks(buf).t2.first == 7, vim.inspect(H.marks(buf)))

H.finish('PASS: coauthor end to end: comment, locked submit, stub agent (list/edit/move/reply/done), round end, orphan re-anchor, diff, reply, next round.')
