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
  rust_analyzer = {
    executable = 'rust-analyzer',
    dirs = { 'rust-lsp' },
    -- Prebuilt standalone server; no Rust toolchain needed to install it.
    requires = { 'curl', windows and 'tar' or 'gzip' },
    install = function(run)
      local uname = vim.uv.os_uname()
      local arch = (uname.machine == 'arm64' or uname.machine == 'aarch64') and 'aarch64' or 'x86_64'
      local target, archive
      if windows then
        target, archive = arch .. '-pc-windows-msvc', '.zip'
      elseif uname.sysname == 'Darwin' then
        target, archive = arch .. '-apple-darwin', '.gz'
      else
        target, archive = arch .. '-unknown-linux-gnu', '.gz'
      end
      local dir = vim.fn.stdpath('data') .. '/rust-lsp'
      local download = dir .. '/rust-analyzer' .. archive
      vim.fn.mkdir(dir, 'p')
      run({ 'curl', '-fsSL', '-o', download,
        ('https://github.com/rust-lang/rust-analyzer/releases/download/%s/rust-analyzer-%s%s')
          :format('2026-11-02', target, archive) })
      if windows then
        -- bsdtar, shipped with Windows, extracts rust-analyzer.exe from the zip.
        run({ 'tar', '-xf', download, '-C', dir })
        vim.fn.delete(download)
      else
        run({ 'gzip', '-df', download })
        vim.fn.setfperm(dir .. '/rust-analyzer', 'rwxr-xr-x')
      end
    end,
  },
  ts_ls = {
    -- TypeScript 7's compiler binary is also its language server (`tsc --lsp`).
    executable = 'tsc',
    dirs = { 'typescript-lsp/node_modules/.bin' },
    requires = { 'npm' },
    install = function(run)
      -- exepath() resolves npm.cmd on Windows, which a bare name would not.
      run({ vim.fn.exepath('npm'), 'install', '--prefix', vim.fn.stdpath('data') .. '/typescript-lsp',
        '--no-package-lock', '--no-fund', '--no-audit', 'typescript@7.0.2' })
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
