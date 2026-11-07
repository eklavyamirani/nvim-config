-- Install language servers and Treesitter parsers into stdpath('data'):
-- `nvim -l scripts/install_deps.lua [target...]`.
-- Runs through Neovim so it behaves the same on Windows, and honours XDG_DATA_HOME/NVIM_APPNAME.
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, 'S').source:sub(2))))
vim.opt.runtimepath:prepend(root)

local servers = require('config.lsp_servers').servers
local targets = vim.tbl_extend('error', {}, servers)
-- Parsers are a dependency like the servers: installing them up front means a
-- session never opens a buffer whose parser is still compiling. They need the
-- plugins, so install them from a Neovim that loads the full configuration.
-- Not part of the default set: CI installs the Treesitter CLI after the
-- servers, and its test runs install the parsers they need themselves.
targets.parsers = {
  requires = { 'tree-sitter' },
  install = function(run)
    -- No escape sequences in this command: a newline inside it would reach the
    -- child as a real line break, and the Lua syntax error that follows leaves
    -- headless Neovim waiting forever.
    run({ vim.v.progpath, '--headless', '--cmd', 'set runtimepath^=' .. root, '-u', root .. '/init.lua',
      '-c', "lua local ok, err = pcall(require('config.treesitter').install) "
        .. "if not ok then print(tostring(err)) vim.cmd('cquit') end vim.cmd('qa!')" }, 900000)
  end,
}

local names = #arg > 0 and arg or vim.tbl_keys(servers)
table.sort(names)

-- `timeout` bounds commands that could stall indefinitely, so a wedged child
-- fails the install instead of hanging it.
local function run(cmd, timeout)
  io.stdout:write('$ ' .. table.concat(cmd, ' ') .. '\n')
  local write = function(_, data) if data then io.stdout:write(data) end end
  local result = vim.system(cmd, { stdout = write, stderr = write }):wait(timeout)
  if result.code ~= 0 then
    error(('command failed with exit code %d%s'):format(result.code,
      result.signal ~= 0 and (' (signal %d)'):format(result.signal) or ''), 0)
  end
end

local failed = {}
for _, name in ipairs(names) do
  local target = targets[name]
  io.stdout:write(('==> %s\n'):format(name))
  local ok, err = pcall(function()
    if not target then error('unknown target; expected one of: ' .. table.concat(vim.tbl_keys(targets), ', '), 0) end
    for _, tool in ipairs(target.requires) do
      if vim.fn.executable(tool) == 0 then error(tool .. ' is not on PATH; see lsp/README.md for prerequisites', 0) end
    end
    target.install(run, root)
  end)
  if not ok then
    table.insert(failed, name)
    io.stderr:write(('%s: %s\n'):format(name, err))
  end
end

if #failed > 0 then
  io.stderr:write('failed: ' .. table.concat(failed, ', ') .. '\n')
  os.exit(1)
end
io.stdout:write('Installed into ' .. vim.fn.stdpath('data') .. '\n')
