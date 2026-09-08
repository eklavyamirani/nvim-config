-- Loaded with the real init.lua: this is the executable specification for the
-- editor-wide customizations recorded in CUSTOMIZATIONS.md.
local function mapping(mode, lhs, description)
  local found = vim.fn.maparg(lhs, mode, false, true)
  assert(found and found.desc == description, ('missing %s mapping %s (%s)'):format(mode, lhs, description))
  return found
end

assert(vim.g.mapleader == ' ' and vim.g.maplocalleader == ' ')
local expected_options = {
  number = true, relativenumber = true, undofile = true, clipboard = 'unnamedplus',
  title = true, ruler = false, showmode = false, showcmd = false, numberwidth = 4,
  smarttab = true, expandtab = true, shiftwidth = 2, tabstop = 8, list = true,
  cursorline = true, scrolloff = 10, termguicolors = true,
}
for name, expected in pairs(expected_options) do
  assert(vim.o[name] == expected, ('option %s: expected %s, got %s'):format(name, expected, vim.o[name]))
end
assert(vim.opt.listchars:get().tab == '» ' and vim.opt.listchars:get().trail == '·')

local maps = {
  n = {
    ['<leader>ed'] = 'mini.files', ['<leader>ei'] = 'init.lua', ['<leader>?'] = 'Open cheatsheet in a tab',
    ['<leader>ay'] = 'AI: yank current line to clipboard', ['<leader>aY'] = 'AI: yank whole buffer to clipboard',
    ['<leader>dv'] = 'Diffview: open (working tree)', ['<leader>dm'] = 'Diffview: review branch vs default',
    ['<leader>dh'] = 'Diffview: file history', ['<leader>dH'] = 'Diffview: branch history',
    ['<leader>dc'] = 'Diffview: close', ['<leader>df'] = 'Diffview: toggle file panel',
    ['<leader>ff'] = 'Find files', ['<leader>fg'] = 'Live grep', ['<leader>fb'] = 'Buffers',
    ['<leader>fh'] = 'Help tags', ['<leader>fr'] = 'Resume last picker', ['<leader>f/'] = 'Grep current buffer',
    ['<leader>ao'] = 'Review: organize files in Diffview panel', [']r'] = 'Review: next file in panel order',
    ['[r'] = 'Review: previous file in panel order', ['<leader>ae'] = 'Review: explain beside the diff',
    ['<leader>ap'] = 'Review: pin selected context', ['<leader>af'] = 'Review: focus explanation',
    ['<leader>aq'] = 'Review: ask a follow-up', ['<leader>an'] = 'Review: edit pinned notes',
    ['<leader>ar'] = 'Review: return to code', ['<leader>ax'] = 'Review: close support panes',
  },
  x = { ['<leader>ay'] = 'AI: yank selection to clipboard', ['<leader>ae'] = 'Review: explain beside the diff',
    ['<leader>ap'] = 'Review: pin selected context' },
}
for mode, entries in pairs(maps) do
  for lhs, description in pairs(entries) do mapping(mode, lhs, description) end
end

for _, module in ipairs({ 'mini.files', 'mini.notify', 'lualine', 'which-key', 'colorizer', 'render-markdown',
  'code-review', 'fzf-lua', 'diffview', 'gitsigns', 'Comment', 'lint', 'nvim-treesitter' }) do
  assert(pcall(require, module), 'plugin module unavailable: ' .. module)
end
assert(vim.fn.exists(':ReviewContext') == 2 and vim.fn.exists(':ReviewRoute') == 2)

local autocmds = vim.api.nvim_get_autocmds({})
local events = {}
for _, autocmd in ipairs(autocmds) do events[autocmd.event] = true end
for _, event in ipairs({ 'VimEnter', 'FileType', 'BufWritePost', 'BufReadPost' }) do
  assert(events[event], 'missing configured autocmd: ' .. event)
end

-- Exercise the custom whole-buffer clipboard formatter without requiring a GUI clipboard provider.
local copied = { {}, 'v' }
vim.g.clipboard = {
  name = 'CI memory clipboard',
  copy = {
    ['+'] = function(lines, regtype) copied = { lines, regtype } end,
    ['*'] = function(lines, regtype) copied = { lines, regtype } end,
  },
  paste = {
    ['+'] = function() return copied end,
    ['*'] = function() return copied end,
  },
}
vim.cmd.enew()
vim.bo.filetype = 'lua'
vim.api.nvim_buf_set_name(0, vim.fn.getcwd() .. '/clipboard-example.lua')
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'local one = 1', 'return one' })
mapping('n', '<leader>aY', 'AI: yank whole buffer to clipboard').callback()
local clipboard = vim.fn.getreg('+')
assert(clipboard:find('@clipboard%-example.lua:1%-2') and clipboard:find('1  local one = 1', 1, true),
  'AI clipboard format changed')

print('PASS: startup, settings, plugins, commands, autocmds, global mappings and AI clipboard formatting.')
vim.cmd('qa!')
