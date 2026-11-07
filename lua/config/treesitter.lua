local M = {}

-- Parsers to keep installed. FileType matches Neovim's detected filetype, not
-- the parser name or the file extension, so parsers whose names differ need an
-- explicit mapping:
-- Extension | Filetype        | Treesitter parser
-- .md       | markdown        | markdown
-- .cs       | cs              | c_sharp
-- .tsx      | typescriptreact | tsx
M.languages = { 'lua', 'vim', 'vimdoc', 'markdown', 'markdown_inline', 'bash', 'json', 'yaml',
  'c_sharp', 'rust', 'typescript', 'tsx', 'javascript' }
local filetypes = { c_sharp = 'cs', tsx = 'typescriptreact' }

-- The filetypes M.languages highlight, for an autocmd pattern.
function M.patterns()
  return vim.tbl_map(function(language) return filetypes[language] or language end, M.languages)
end

-- Starting a parser that is not on disk yet raises, which a missing parser
-- turned into an error on the first file of that type. Highlighting such a
-- buffer is this module's job once the install finishes, not the user's.
local function start(buf)
  if not pcall(vim.treesitter.start, buf) then return false end
  vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
  return true
end

-- The install started at startup, so a blocking install waits on the work
-- already in flight instead of queuing a second pass over the same parsers.
local pending

function M.setup()
  local ok, ts = pcall(require, 'nvim-treesitter')
  if not ok then return end
  local patterns = M.patterns()
  vim.api.nvim_create_autocmd('FileType', {
    pattern = patterns,
    callback = function(ev) start(ev.buf) end,
  })
  local wanted = {}
  for _, pattern in ipairs(patterns) do wanted[pattern] = true end
  pending = ts.install(M.languages)
  -- Highlight buffers that were opened while their parser was still compiling,
  -- rather than leaving them plain until the file is reopened.
  pending:await(vim.schedule_wrap(function()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf)
        and wanted[vim.bo[buf].filetype]
        and not vim.treesitter.highlighter.active[buf]
      then
        start(buf)
      end
    end
  end))
end

-- Blocking install for scripts/install_deps.lua. Raises when a parser fails.
function M.install(timeout)
  local task = pending or require('nvim-treesitter').install(M.languages)
  if not task:wait(timeout or 600000) then
    error('not every parser installed; see the messages above', 0)
  end
end

return M
