require('config.plugins')

-- Basic settings -- 
vim.o.number = true  -- Show line numbers
vim.o.relativenumber = false -- Use relative line numbers
vim.g.mapleader = ' '    -- Set space as leader key
vim.g.maplocalleader = ' '  -- Optional: Set space as local leader key (for buffer-local mappings)
vim.o.undofile = true
vim.o.clipboard = "unnamedplus"
vim.o.title = true
vim.o.tabstop = 2
vim.o.ruler = false
vim.o.showmode = false
vim.o.showcmd = false
vim.o.numberwidth = 4
vim.o.smarttab = true
vim.o.expandtab = true -- we use space instead of tab around here.
vim.o.shiftwidth = 2
vim.o.tabstop = 8 -- identify tabs easily.

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
vim.api.nvim_set_keymap('n', '<leader>e', ':lua MiniFiles.open()<CR>', { noremap = trdf;ue, silent = true })
vim.keymap.set('n',"<leader>t", ":NvimTreeToggle<CR>") -- open nvim tree file explorer
