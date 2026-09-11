-- Install language servers into stdpath('data'): `nvim -l scripts/install_deps.lua [server...]`.
-- Runs through Neovim so it behaves the same on Windows, and honours XDG_DATA_HOME/NVIM_APPNAME.
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, 'S').source:sub(2))))
vim.opt.runtimepath:prepend(root)
local servers = require('config.lsp_servers').servers

local names = #arg > 0 and arg or vim.tbl_keys(servers)
table.sort(names)

local function run(cmd)
  io.stdout:write('$ ' .. table.concat(cmd, ' ') .. '\n')
  local write = function(_, data) if data then io.stdout:write(data) end end
  local result = vim.system(cmd, { stdout = write, stderr = write }):wait()
  if result.code ~= 0 then error(('command failed with exit code %d'):format(result.code), 0) end
end

local failed = {}
for _, name in ipairs(names) do
  local server = servers[name]
  io.stdout:write(('==> %s\n'):format(name))
  local ok, err = pcall(function()
    if not server then error('unknown server; expected one of: ' .. table.concat(vim.tbl_keys(servers), ', '), 0) end
    for _, tool in ipairs(server.requires) do
      if vim.fn.executable(tool) == 0 then error(tool .. ' is not on PATH; see lsp/README.md for prerequisites', 0) end
    end
    server.install(run, root)
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
