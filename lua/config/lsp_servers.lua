local M = {}

-- Servers install under stdpath('data'), independently of project dependencies.
-- `dirs` lists candidate install directories; pip venvs use Scripts\ on Windows.
M.servers = {
  basedpyright = {
    executable = 'basedpyright-langserver',
    dirs = { 'python-lsp/bin', 'python-lsp/Scripts' },
  },
  csharp_ls = {
    executable = 'csharp-ls',
    dirs = { 'csharp-lsp' },
  },
}

-- exepath() applies PATHEXT on Windows, so the extensionless name also finds .exe/.cmd installs.
function M.executable(name)
  local server = M.servers[name]
  for _, dir in ipairs(server.dirs) do
    local path = vim.fn.exepath(vim.fn.stdpath('data') .. '/' .. dir .. '/' .. server.executable)
    if path ~= '' then return path end
  end
  return server.executable
end

return M
