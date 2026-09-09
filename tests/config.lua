-- Loaded with the real init.lua: this is the executable specification for the
-- editor-wide customizations recorded in CUSTOMIZATIONS.md.
local function mapping(mode, lhs, description)
  local found = vim.fn.maparg(lhs, mode, false, true)
  assert(found and found.desc == description, ('missing %s mapping %s (%s)'):format(mode, lhs, description))
  return found
end

local manifest = vim.json.decode(table.concat(vim.fn.readfile('tests/customizations.json'), '\n'))
assert(vim.g.mapleader == ' ' and vim.g.maplocalleader == ' ')
for name, expected in pairs(manifest.options) do
  assert(vim.o[name] == expected, ('option %s: expected %s, got %s'):format(name, expected, vim.o[name]))
end
assert(vim.deep_equal(vim.opt.listchars:get(), manifest.listchars), 'listchars do not match the manifest')

for mode, entries in pairs(manifest.keymaps) do
  for lhs, description in pairs(entries) do mapping(mode, lhs, description) end
end

for _, module in pairs(manifest.plugins) do
  assert(pcall(require, module), 'plugin module unavailable: ' .. module)
end
assert(vim.fn.exists(':ReviewContext') == 2 and vim.fn.exists(':ReviewRoute') == 2)

local autocmds = vim.api.nvim_get_autocmds({})
local events = {}
for _, autocmd in ipairs(autocmds) do events[autocmd.event] = true end
for _, event in ipairs(manifest.autocmd_events) do
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
