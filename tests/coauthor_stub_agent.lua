-- A stand-in for Copilot CLI / Claude Code in a headless coauthor round:
-- `nvim -l tests/coauthor_stub_agent.lua MODE DOC COAUTHOR`, run in the
-- document's directory. MODE: done, linger, exit, fail or hang. It uses only the coauthor CLI and file writes, like an
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
