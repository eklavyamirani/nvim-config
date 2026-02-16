local vim = vim
local Plug = vim.fn['plug#']

vim.call('plug#begin')

Plug('nvim-lualine/lualine.nvim') --statusline
Plug('nvim-tree/nvim-web-devicons')
Plug('nvim-mini/mini.files', { ['branch'] = 'stable'} ) -- file explorer
Plug('nvim-mini/mini.diff', { ['branch'] = 'stable'} ) -- diff helper
Plug('nvim-mini/mini.notify', { ['branch'] = 'stable'} ) -- notifications
Plug('catppuccin/nvim', { ['as'] = 'catppuccin' }) --colorscheme
Plug('folke/which-key.nvim') --mappings popup
Plug('nvim-treesitter/nvim-treesitter') --improved syntax
Plug('mfussenegger/nvim-lint') --async linter
-- disabling, trying out mini files instead
-- Plug('nvim-tree/nvim-tree.lua') --file explorer
Plug('windwp/nvim-autopairs') --autopairs 
Plug('lewis6991/gitsigns.nvim') --git
Plug('numToStr/Comment.nvim') --easier comments
Plug('norcalli/nvim-colorizer.lua') --color highlight
Plug('MeanderingProgrammer/render-markdown.nvim') --render md inline

vim.call('plug#end')

-- setup plugins
require('mini.files').setup()
require('mini.diff').setup()
-- require('nvim-tree').setup({
--   sync_root_with_cwd = true,
--   update_cwd = true,
-- })
-- TODO: do a git check against remote to see if new config is available
-- and create notification to update config
require('mini.notify').setup()
require('nvim-autopairs').setup()
require('lualine').setup()
-- require('gitsigns').setup()
require("Comment").setup({
  ---Add a space b/w comment and the line
  padding = true,
  ---Whether the cursor should stay at its position
  sticky = true,
  ---Lines to be ignored while (un)comment
  ignore = nil,
  ---LHS of toggle mappings in NORMAL mode
  toggler = {
    ---Line-comment toggle keymap
    line = "gcc",
    ---Block-comment toggle keymap
    block = "gb",
  },
  -- -LHS of operator-pending mappings in NORMAL and VISUAL mode
  opleader = {
    ---Line-comment keymap
    line = "gcc",
    ---Block-comment keymap
    block = "gb",
  },
  ---LHS of extra mappings
  extra = {
    ---Add comment on the line above
    above = "gcO",
    ---Add comment on the line below
    below = "gco",
    ---Add comment at the end of line
    eol = "gcA",
  },
  ---Enable keybindings
  ---NOTE: If given `false` then the plugin won't create any mappings
  mappings = {
    ---Operator-pending mapping; `gcc` `gbc` `gc[count]{motion}` `gb[count]{motion}`
    basic = true,
    ---Extra mapping; `gco`, `gcO`, `gcA`
    extra = true,
  },
  ---Function to call before (un)comment
  pre_hook = nil,
  ---Function to call after (un)comment
  post_hook = nil,
})
