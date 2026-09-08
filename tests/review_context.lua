local api = vim.api
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.g.mapleader = ' '
vim.o.columns, vim.o.lines = 220, 70
local temp = vim.fn.tempname()
vim.fn.mkdir(temp .. '/repo/.git', 'p')
local root = temp .. '/repo'
local source_path = root .. '/example.sh'
vim.fn.writefile({ 'before', '. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"', 'after' }, source_path)
vim.cmd.edit(source_path)
local source_win, source_buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
api.nvim_win_set_cursor(source_win, { 2, 4 })
local captured = {}
local module = require('config.review_context')
module.setup({ command = function(prompt)
  captured[#captured + 1] = prompt
  return { 'python3', '-c', 'import sys,time; time.sleep(float(sys.argv[1])); print(sys.argv[2])', '0.05', 'Meaning: load the harness.\nKeep: source runs in this shell.' }
end })

local function answer_buffer()
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_get_name(buf):match('^review%-context://') then return buf end
  end
end
local function answer()
  local found = ''
  for _, win in ipairs(api.nvim_list_wins()) do
    local buf = api.nvim_win_get_buf(win)
    if api.nvim_buf_get_name(buf):match('^review%-context://') then
      found = table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
    end
  end
  return found
end
local function wait_for(text)
  assert(vim.wait(3000, function() return answer():find(text, 1, true) ~= nil end), answer())
end

local original_input, submit, input_options = vim.ui.input
vim.ui.input = function(opts, callback) input_options, submit = opts, callback end
local function ask_key(mode) vim.fn.maparg(' aa', mode, false, true).callback() end

-- Ask directly without first requesting an explanation; cancel sends nothing.
ask_key('n')
assert(input_options.prompt:find('example.sh:2', 1, true))
assert(#captured == 0 and #api.nvim_list_wins() == 1, 'input alone sent a request or opened panes')
submit(nil)
ask_key('n'); submit('   ')
assert(#captured == 0 and #api.nvim_list_wins() == 1, 'cancel/empty input had side effects')
ask_key('n')
api.nvim_buf_set_lines(source_buf, 2, 3, false, { 'CHANGED_WHILE_TYPING' })
submit('  Why does sourcing preserve variables?  ')
wait_for('Meaning: load')
assert(captured[1]:find('QUESTION: Why does sourcing preserve variables?', 1, true), 'specific question missing')
assert(not captured[1]:find('PREVIOUS EXPLANATION:', 1, true), 'new question inherited an old explanation')
assert(captured[1]:find('3  after', 1, true) and not captured[1]:find('CHANGED_WHILE_TYPING', 1, true), 'input changed captured context')
assert(answer():find('**Question:** Why does sourcing preserve variables?', 1, true), 'answer omitted question')
assert(api.nvim_get_current_win() == source_win, 'question moved focus out of code')
local last_path = vim.fn.stdpath('state') .. '/review-context/' .. vim.fn.sha256(vim.uv.fs_realpath(root)):sub(1, 20) .. '/last.json'
local saved = vim.json.decode(table.concat(vim.fn.readfile(last_path), '\n'))
assert(saved.answer:find('Why does sourcing preserve variables?', 1, true), 'question was not persisted with answer')
module.close()
api.nvim_buf_set_lines(source_buf, 2, 3, false, { 'after' })
captured = {}

module.explain('line')
assert(api.nvim_get_current_win() == source_win, 'opening support moved focus')
assert(vim.deep_equal(api.nvim_win_get_cursor(source_win), { 2, 4 }), 'opening support moved cursor')
wait_for('Meaning: load')
assert(captured[1]:find('2  . "$(dirname', 1, true), 'source line numbering lost')
assert(captured[1]:find('working buffer snapshot', 1, true), 'revision missing')

-- Exact charwise selection, including when the cursor precedes its anchor.
api.nvim_win_set_cursor(source_win, { 2, 13 })
vim.cmd.normal({ args = { 'v6h' }, bang = true })
local expected = table.concat(vim.fn.getregion(vim.fn.getpos('v'), vim.fn.getpos('.'), { type = 'v' }), '\n')
module.explain('visual')
wait_for('Meaning: load')
assert(captured[2]:find('SELECTED EXPRESSION:\n' .. expected .. '\n', 1, true), 'selected columns not preserved')

module.focus()
api.nvim_win_set_cursor(0, { 4, 0 })
module.pin('line')
module.notes()
local note_path = api.nvim_buf_get_name(0)
assert(note_path:find('/review-context/', 1, true))
assert(table.concat(vim.fn.readfile(note_path), '\n'):find('source runs in this shell', 1, true), 'pin not saved')
assert(vim.uv.fs_stat(note_path).mode % 512 == 384, 'notes must be private')
api.nvim_buf_set_lines(0, -1, -1, false, { 'An edited private note.' })
module.return_to_code()
assert(api.nvim_get_current_win() == source_win)
assert(table.concat(vim.fn.readfile(note_path), '\n'):find('edited private note', 1, true), 'leaving notes did not save')

-- Use an actual diff buffer's contents, not a file reread from disk.
local old = api.nvim_create_buf(false, true)
api.nvim_buf_set_name(old, 'diffview://' .. root .. '/.git/deadbeef/example.sh')
api.nvim_buf_set_lines(old, 0, -1, false, { 'OLD_REVISION_VALUE=42' })
package.loaded['diffview.vcs.rev'] = { RevType = { COMMIT = 1, STAGE = 2, CUSTOM = 3 } }
package.loaded['diffview.lib'] = { get_current_view = function()
  return { cur_layout = { windows = { { file = { bufnr = old, absolute_path = source_path,
    rev = { type = 1, commit = 'deadbeef01234567' } } } } } }
end }
api.nvim_win_set_buf(source_win, old)
api.nvim_win_set_cursor(source_win, { 1, 0 })
module.explain('line')
wait_for('Meaning: load')
assert(captured[3]:find('OLD_REVISION_VALUE=42', 1, true), 'old revision replaced by working tree')
assert(captured[3]:find('commit deadbeef01234567', 1, true), 'commit identity missing')
assert(captured[3]:find('edited private note', 1, true), 'pinned context missing from request')

-- A selected question captures exact columns and the old revision before input.
local value_col = ('OLD_REVISION_VALUE=42'):find('42', 1, true) - 1
api.nvim_win_set_cursor(source_win, { 1, value_col })
vim.cmd.normal({ args = { 'vl' }, bang = true })
local question_position = api.nvim_win_get_cursor(source_win)
ask_key('x')
api.nvim_buf_set_lines(old, 0, -1, false, { 'CHANGED_WHILE_QUESTION_WAS_OPEN' })
api.nvim_win_set_cursor(source_win, { 1, 0 })
submit('Why is this value 42?')
wait_for('Meaning: load')
assert(captured[4]:find('SELECTED EXPRESSION:\n42\n', 1, true), 'question lost selected columns')
assert(captured[4]:find('commit deadbeef01234567', 1, true), 'question lost selected revision')
assert(not captured[4]:find('CHANGED_WHILE_QUESTION_WAS_OPEN', 1, true), 'question recaptured code after input')
assert(not captured[4]:find('PREVIOUS EXPLANATION:', 1, true), 'selected question reused prior answer')
module.return_to_code()
assert(vim.deep_equal(api.nvim_win_get_cursor(source_win), question_position), 'return lost question source position')
module.ask(); submit('Could it be unset?')
wait_for('Meaning: load')
assert(captured[5]:find('PREVIOUS EXPLANATION:', 1, true) and captured[5]:find('Why is this value 42?', 1, true), 'follow-up lost question/answer')
assert(captured[5]:find('SELECTED EXPRESSION:\n42\n', 1, true), 'follow-up left the question selection')
local prior_answer, prior_count = answer(), #captured
ask_key('n'); submit(nil)
assert(answer() == prior_answer and #captured == prior_count, 'cancel replaced existing answer')
vim.ui.input = original_input

-- A slow earlier response must not overwrite the newer selection.
module.setup({ command = function(prompt)
  local slow = prompt:find('SLOW_VALUE', 1, true)
  return { 'python3', '-c', 'import sys,time; time.sleep(float(sys.argv[1])); print(sys.argv[2])', slow and '0.5' or '0.01', slow and 'STALE_RESULT' or 'FRESH_RESULT' }
end })
api.nvim_buf_set_lines(old, 0, -1, false, { 'SLOW_VALUE' })
module.explain('line')
api.nvim_buf_set_lines(old, 0, -1, false, { 'FAST_VALUE' })
module.explain('line')
wait_for('FRESH_RESULT')
vim.wait(700, function() return false end)
assert(not answer():find('STALE_RESULT', 1, true), 'stale answer won the race')
module.close()
assert(#api.nvim_list_wins() == 1, 'support windows left behind')
module.open()
assert(answer():find('FRESH_RESULT', 1, true), 'reopen lost answer')
module.close()

-- Restoring after a module reload uses persisted source and answer.
package.loaded['config.review_context'] = nil
local restored = require('config.review_context')
restored.setup({ command = function() return { 'false' } end })
api.nvim_win_set_buf(source_win, source_buf)
restored.open()
assert(answer():find('FRESH_RESULT', 1, true), 'last answer was not persisted')
restored.close()
restored.explain('line')
wait_for('Explanation unavailable')
restored.close()

print('PASS: direct questions, cancellation, captured selections/revisions, follow-ups, question persistence, focus/cursor, pins, request ordering and backend errors.')
vim.cmd('qa!')
