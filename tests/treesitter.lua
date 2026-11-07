-- Loaded with the real init.lua: parser/filetype mapping and highlighting start.
local treesitter = require('config.treesitter')
local ok, err = xpcall(function()
  local patterns = treesitter.patterns()
  local function matches(filetype) return vim.tbl_contains(patterns, filetype) end
  assert(matches('cs') and not matches('c_sharp'), 'C# must be matched by its filetype, not its parser')
  assert(matches('typescriptreact') and not matches('tsx'), '.tsx buffers must be matched by their filetype')
  assert(matches('rust') and matches('typescript') and matches('javascript'), 'a configured language is unmatched')

  -- Parsers install asynchronously, so a parser that cannot start must not turn
  -- the first file of its type into an error, nor leave an indentexpr behind.
  local original = vim.treesitter.start
  vim.treesitter.start = function() error('no parser installed') end
  local unparsed = vim.api.nvim_create_buf(false, true)
  local started, failure = pcall(function() vim.bo[unparsed].filetype = 'rust' end)
  vim.treesitter.start = original
  assert(started, 'a missing parser raised: ' .. tostring(failure))
  -- Neovim's own indent/rust.vim sets indentexpr; only Treesitter's must be absent.
  assert(not vim.bo[unparsed].indentexpr:find('nvim%-treesitter'),
    'the Treesitter indentexpr was set without a parser')

  -- Startup installs parsers asynchronously; a fresh CI runner has no tsx parser yet.
  require('nvim-treesitter').install({ 'tsx' }):wait(180000)
  assert(vim.treesitter.language.add('tsx'), 'tsx parser installation failed')
  assert(vim.treesitter.language.get_lang('typescriptreact') == 'tsx', 'wrong .tsx parser mapping')
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'export const App = () => <div />;' })
  vim.bo[buf].filetype = 'typescriptreact'
  assert(vim.treesitter.highlighter.active[buf], 'typescriptreact highlighting did not start')
  assert(vim.bo[buf].indentexpr:find('nvim%-treesitter'), 'treesitter indentexpr was not set')
end, debug.traceback)
if not ok then print(err); vim.cmd('cquit') end
print('PASS: parser/filetype mapping, missing-parser guard, and highlighting on .tsx buffers.')
vim.cmd('qa!')
