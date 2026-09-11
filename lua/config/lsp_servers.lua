local M = {}

local windows = vim.fn.has('win32') == 1

-- exepath() applies PATHEXT on Windows, so extensionless names also find .exe/.cmd installs.
local function find(dirs, executable)
  for _, dir in ipairs(dirs) do
    local path = vim.fn.exepath(vim.fn.stdpath('data') .. '/' .. dir .. '/' .. executable)
    if path ~= '' then return path end
  end
end

-- Every enabled server, where it installs under stdpath('data') (independently of
-- project dependencies), and how scripts/install_deps.lua installs it.
-- `requires` lists tools that must already be on PATH.
M.servers = {
  basedpyright = {
    executable = 'basedpyright-langserver',
    -- pip venvs use Scripts\ on Windows.
    dirs = { 'python-lsp/bin', 'python-lsp/Scripts' },
    requires = { windows and 'python' or 'python3' },
    install = function(run, root)
      local venv = vim.fn.stdpath('data') .. '/python-lsp'
      run({ windows and 'python' or 'python3', '-m', 'venv', venv })
      local python = find({ 'python-lsp/bin', 'python-lsp/Scripts' }, 'python')
      run({ python, '-m', 'pip', 'install', '--upgrade', '-r', root .. '/lsp/requirements.txt' })
    end,
  },
  csharp_ls = {
    executable = 'csharp-ls',
    dirs = { 'csharp-lsp' },
    requires = { 'dotnet' },
    install = function(run)
      local verb = find({ 'csharp-lsp' }, 'csharp-ls') and 'update' or 'install'
      run({ 'dotnet', 'tool', verb, '--tool-path', vim.fn.stdpath('data') .. '/csharp-lsp',
        'csharp-ls', '--version', '0.27.0' })
    end,
  },
}

function M.executable(name)
  local server = M.servers[name]
  return find(server.dirs, server.executable) or server.executable
end

return M
