require('config.plugins')

-- Basic settings -- 
vim.o.number = true  -- Show line numbers
vim.o.relativenumber = false -- Use relative line numbers
vim.g.mapleader = ' '    -- Set space as leader key
vim.g.maplocalleader = ' '  -- Optional: Set space as local leader key (for buffer-local mappings)
vim.opt.undofile = true

-- Sets how neovim will display certain whitespace characters in the editor.
--  See `:help 'list'`
--  and `:help 'listchars'`
vim.opt.list = true
vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }

-- Show which line your cursor is on
vim.opt.cursorline = true

-- Minimal number of screen lines to keep above and below the cursor.
vim.opt.scrolloff = 10

-- keymaps --
vim.api.nvim_set_keymap('n', '<leader>e', ':lua MiniFiles.open()<CR>', { noremap = true, silent = true })
