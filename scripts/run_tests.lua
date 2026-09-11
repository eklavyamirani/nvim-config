-- Run test suites on any platform: `nvim -l scripts/run_tests.lua [suite...]`.
-- Each test runs in a fresh headless Neovim, inheriting this process's environment.
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, 'S').source:sub(2))))
local python = vim.fn.executable('python3') == 1 and 'python3' or 'python'

local suites = {
  { 'check', { python, 'scripts/check_config.py' } },
  { 'config', 'init.lua', 'tests/config.lua' },
  { 'config', 'init.lua', 'tests/csharp_lsp.lua' },
  { 'config', 'NONE', 'tests/lsp_servers.lua' },
  { 'review', 'NONE', 'tests/review_context.lua' },
  { 'review', 'NONE', 'tests/review_route.lua' },
  { 'review', 'NONE', 'tests/review_tree.lua' },
  { 'review', 'NONE', 'tests/review_group_tree.lua' },
  { 'review', 'NONE', 'tests/review_worktree.lua' },
  { 'review', 'init.lua', 'tests/review_startup.lua' },
  { 'review', 'init.lua', 'tests/review_reading.lua' },
  -- Needs the servers from scripts/install_deps.lua.
  { 'lsp', 'init.lua', 'tests/python_lsp.lua' },
  { 'lsp', 'init.lua', 'tests/diffview_lsp.lua' },
}

local selected = {}
for _, name in ipairs(#arg > 0 and arg or { 'check', 'config', 'review' }) do selected[name] = true end

local write = function(_, data) if data then io.stdout:write(data) end end
local failed = {}
for _, test in ipairs(suites) do
  local suite, init, file = test[1], test[2], test[3]
  if selected[suite] then
    local cmd = type(init) == 'table' and init or {
      vim.v.progpath, '--headless', '--cmd', 'set runtimepath^=' .. root,
      '-u', init, '-c', ("lua dofile('%s')"):format(file),
    }
    local label = file or table.concat(cmd, ' ')
    io.stdout:write(('==> %s\n'):format(label))
    local result = vim.system(cmd, { cwd = root, stdout = write, stderr = write }):wait()
    io.stdout:write('\n')
    if result.code ~= 0 then table.insert(failed, label) end
  end
end

if #failed > 0 then
  io.stderr:write('FAILED:\n  ' .. table.concat(failed, '\n  ') .. '\n')
  os.exit(1)
end
