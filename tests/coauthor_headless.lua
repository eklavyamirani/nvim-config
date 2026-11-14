-- Coauthor headless submit (experimental) with a stub agent: success (the
-- agent runs `coauthor done`), exit without `done`, failure, and cancel; plus
-- the real agents' permission flags.
local api = vim.api
local H = dofile('tests/coauthor_setup.lua')
local coauthor, cli = H.coauthor, H.cli

local stub = H.root .. '/tests/coauthor_stub_agent.lua'
local mode
local started = {}
coauthor.options.agent_command = function(prompt, ctx)
  table.insert(started, { prompt = prompt, ctx = ctx })
  return { vim.v.progpath, '-l', stub, mode, ctx.relative, H.binary }
end

local function wait(condition, message)
  assert(vim.wait(20000, function() return coauthor.idle() and condition() end, 20), message)
end

local function notice(pattern)
  for i = #H.notices, 1, -1 do
    if H.notices[i].message:find(pattern, 1, true) then return H.notices[i] end
  end
end

local path = H.doc('headless.md', { '# Headless', 'First point.', 'Second point.' })
vim.cmd.edit(path)
local buf = api.nvim_get_current_buf()
H.idle()

local function comment(line, text)
  H.answer(text)
  api.nvim_win_set_cursor(0, { line, 0 })
  coauthor.comment('line')
  H.idle()
end

local function round_over()
  return coauthor.docs[buf].round == nil and not vim.bo[buf].readonly
end

-- 1. Success: the agent edits, replies and runs `coauthor done` itself.
comment(2, 'expand')
comment(3, 'fine?')
mode = 'done'
coauthor.submit_headless()
wait(function() return #started == 1 end, 'agent did not start')
assert(started[1].ctx.relative == 'headless.md' and started[1].prompt:find('coauthor list headless.md', 1, true),
  vim.inspect(started[1]))
wait(round_over, 'round did not end after a successful agent')
wait(function() return api.nvim_buf_get_lines(buf, 2, 3, false)[1] == 'Added by the agent.' end, 'not reloaded')
assert(notice('round done · 2 replies · 1 edit · 0 orphaned'), vim.inspect(H.notices))
assert(not notice('agent exited'), 'success reported as a failure')

-- An agent still writing its final message after `coauthor done` is not killed.
comment(1, 'and the title?')
mode = 'linger'
coauthor.submit_headless()
wait(function() return coauthor.docs[buf].round and coauthor.docs[buf].round.job end, 'agent did not start')
local lingering = coauthor.docs[buf].round.job
wait(round_over, 'round did not end on the agent\'s done')
local exit = lingering:wait(10000)
assert(exit.code == 0 and exit.signal == 0, 'the agent was killed after done: ' .. vim.inspect(exit))
assert(not notice('agent exited'), 'a lingering agent was reported as a failure')

-- 2. The agent exits 0 without `coauthor done`: Neovim runs it.
comment(1, 'title?')
mode = 'exit'
coauthor.submit_headless()
wait(round_over, 'round did not end when the agent exited without done')
assert(cli('list', path).round == 'done', 'coauthor done was not run on exit')
wait(function() return api.nvim_buf_get_lines(buf, 1, 2, false)[1] == 'Added by the agent.' end, 'not reloaded')
assert(api.nvim_buf_get_lines(buf, 2, 3, false)[1] == 'Added by the agent.', 'the linger round edit is missing')

-- 3. Failure: the error is reported, and the round still ends with `done`.
comment(1, 'again')
mode = 'fail'
coauthor.submit_headless()
wait(round_over, 'round did not end after a failing agent')
local failure = notice('agent exited with 3')
assert(failure and failure.level == vim.log.levels.ERROR and failure.message:find('simulated failure', 1, true),
  vim.inspect(H.notices))
-- Expected: H.finish fails on any other error notice.
failure.level = vim.log.levels.WARN
assert(cli('list', path).round == 'done')
-- 'again' was a reply inside t3, which the agent answered before failing.
local t3 = H.thread(cli('list', path), 't3').messages
assert(t3[#t3].text == '{no edit} Partial answer before failing.', vim.inspect(t3))

-- 4. Cancel kills a running agent and ends the round without `done`.
comment(1, 'once more')
mode = 'hang'
coauthor.submit_headless()
wait(function() return coauthor.docs[buf].round and coauthor.docs[buf].round.job end, 'agent did not start')
local job = coauthor.docs[buf].round.job
local seen = #H.notices
vim.cmd('CoauthorCancel')
assert(round_over(), 'cancel did not end the round')
assert(vim.wait(10000, function() return job:wait(0) ~= nil end), 'agent still running after cancel')
H.idle()
assert(cli('list', path).round == 'open', 'cancel must not run coauthor done')
for i = seen + 1, #H.notices do
  assert(not H.notices[i].message:find('agent exited', 1, true), 'a cancelled agent was reported as a failure')
end

-- 5. The real agents get only document edits and `coauthor`.
coauthor.options.agent_command = nil
local ctx = { path = path, root = H.temp .. '/docs', relative = 'headless.md' }
vim.g.review_context_provider = 'claude'
local claude = table.concat(coauthor.agent_command('PROMPT', ctx), ' ')
assert(claude:find("--permission-mode dontAsk", 1, true) and claude:find('--allowedTools Bash(coauthor *) Edit(./headless.md)', 1, true),
  claude)
vim.g.review_context_provider = 'copilot'
local copilot, env = coauthor.agent_command('PROMPT', ctx)
copilot = table.concat(copilot, ' ')
assert(copilot:find('--allow-tool=shell(coauthor:*),write(headless.md),read', 1, true) and copilot:find('--no-ask-user', 1, true),
  copilot)
assert(env and env.COPILOT_HOME, 'copilot runs outside the user session list')

H.finish('PASS: coauthor headless submit: success, exit without done, failure, cancel, and agent permissions.')
