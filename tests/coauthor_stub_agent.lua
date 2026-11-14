-- A stand-in for Copilot CLI / Claude Code in a headless coauthor round:
-- `nvim -l tests/coauthor_stub_agent.lua MODE DOC COAUTHOR`, run in the
-- document's directory. MODE: done, linger, exit, fail, hang or e2e. It uses only the coauthor CLI and file writes, like an
-- agent limited to Edit on the document and `coauthor *` in its shell.
local mode, doc, coauthor = arg[1], arg[2], arg[3]

local function run(...)
  local result = vim.system({ coauthor, ... }, { text = true }):wait()
  if result.code ~= 0 then
    io.stderr:write('coauthor failed: ', result.stderr or '', '\n')
    os.exit(2)
  end
  return result.stdout
end

-- Agent edit tools typically write a temp file and rename it into place.
local function write(lines)
  local temp = doc .. '.stub-tmp'
  vim.fn.writefile(lines, temp)
  assert(vim.uv.fs_rename(temp, doc))
end

if mode == 'hang' then
  while true do vim.uv.sleep(200) end
end

-- The end-to-end round: wait for the test's go-ahead (so it can check the
-- lock), then exercise every agent-facing command.
if mode == 'e2e' then
  for _ = 1, 200 do
    if vim.uv.fs_stat(doc .. '.go') then break end
    vim.uv.sleep(100)
  end
  local listing = run('list', doc)
  assert(listing:find('Reply to every thread awaiting ai', 1, true), 'agent rules missing')
  local state = vim.json.decode(run('--json', 'list', doc, '--awaiting', 'ai'))
  assert(#state.threads == 3, 'expected three threads awaiting ai')
  write({ '# Launch plan', '', 'Summary added.', 'Timeline: phase 1 (one week), phase 2 (one week).',
    'Budget line.', 'Owner: platform team.', 'End.' })
  -- t1 was rewritten: re-anchor it. t2's text moved and changed, and this
  -- agent forgets `move` (it becomes an orphan). t3 needs no change.
  run('move', doc, 't1', '4-4')
  run('reply', doc, 't1', '--edited', '4', 'Split the timeline into two phases.')
  run('reply', doc, 't2', '--edited', '6', 'Named the owner.')
  run('reply', doc, 't3', '--no-edit', 'The budget line is fine as is.')
  run('done', doc)
  os.exit(0)
end

local listing = run('list', doc, '--awaiting', 'ai')
assert(listing:find('When you are finished, run `coauthor done DOC`.', 1, true), 'agent rules missing')
local state = vim.json.decode(run('--json', 'list', doc, '--awaiting', 'ai'))
local first = state.threads[1]

if mode == 'fail' then
  run('reply', doc, first.id, '--no-edit', 'Partial answer before failing.')
  io.stderr:write('stub agent: simulated failure\n')
  os.exit(3)
end

local lines = vim.fn.readfile(doc)
table.insert(lines, first.lines[2] + 1, 'Added by the agent.')
write(lines)
run('reply', doc, first.id, '--edited', (first.lines[2] + 1) .. '-' .. (first.lines[2] + 1), 'Added a line.')
for i = 2, #state.threads do
  run('reply', doc, state.threads[i].id, '--no-edit', 'No change needed.')
end
if mode == 'done' or mode == 'linger' then run('done', doc) end
-- Like a real agent, keep working on a final message after `coauthor done`.
if mode == 'linger' then vim.uv.sleep(1500) end
os.exit(0)
