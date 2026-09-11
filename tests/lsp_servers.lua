local repo = vim.fs.dirname(vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, 'S').source:sub(2))))
local data = vim.fn.stdpath('data')
local windows = vim.fn.has('win32') == 1
local exe = windows and '.exe' or ''
-- Where each installer puts the server: pip uses Scripts\ and dotnet adds .exe on Windows.
local expected = {
  basedpyright = data .. '/python-lsp/' .. (windows and 'Scripts' or 'bin') .. '/basedpyright-langserver' .. exe,
  csharp_ls = data .. '/csharp-lsp/csharp-ls' .. exe,
}
-- Windows paths are case-insensitive, and exepath() takes the extension's case from PATHEXT.
local function same_path(a, b)
  a, b = vim.fs.normalize(a), vim.fs.normalize(b)
  if windows then a, b = a:lower(), b:lower() end
  return a == b
end
local created = {}
local function stub(path)
  if vim.uv.fs_stat(path) then return end
  local dir = vim.fs.dirname(path)
  local top = dir
  while not vim.uv.fs_stat(vim.fs.dirname(top)) do top = vim.fs.dirname(top) end
  if not vim.uv.fs_stat(top) then table.insert(created, top) end
  vim.fn.mkdir(dir, 'p')
  vim.fn.writefile({}, path)
  vim.fn.setfperm(path, 'rwxr-xr-x')
  table.insert(created, path)
end
local ok, err = xpcall(function()
  local registered = require('config.lsp_servers').servers
  local configs = {}
  for _, path in ipairs(vim.fn.globpath(repo, 'lsp/*.lua', false, true)) do
    configs[vim.fn.fnamemodify(path, ':t:r')] = true
  end
  for name in pairs(vim.tbl_extend('force', configs, registered, expected)) do
    assert(configs[name] and registered[name] and expected[name],
      name .. ' must have an lsp/ config, a config.lsp_servers entry with install steps, and an expected path here')
    assert(type(registered[name].install) == 'function', name .. ' has no install steps')
  end
  for _, path in pairs(expected) do stub(path) end
  local root = vim.uv.cwd()
  for name, path in pairs(expected) do
    local config = vim.lsp.config[name]
    local cmd, cwd = config.cmd, root
    if type(cmd) == 'function' then
      local original = vim.lsp.rpc.start
      vim.lsp.rpc.start = function(c, _, opts) cmd, cwd = c, opts.cwd end
      local success, failure = pcall(config.cmd, {}, { root_dir = root })
      vim.lsp.rpc.start = original
      assert(success, failure)
    end
    assert(cwd == root, name .. ' did not start in the project root')
    assert(type(cmd) == 'table' and same_path(cmd[1], path),
      ('%s: expected installed server %s, got %s'):format(name, path, type(cmd) == 'table' and cmd[1]))
  end
end, debug.traceback)
for i = #created, 1, -1 do vim.fn.delete(created[i], 'rf') end
if not ok then print(err); vim.cmd('cquit') end
print('PASS: every language server resolves its installed executable on this platform.')
vim.cmd('qa!')
