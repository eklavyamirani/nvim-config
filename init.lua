local config_dir = vim.fn.stdpath('config')

-- Optimized module loader, improves startup performance.
vim.loader.enable()
vim.o.termguicolors = true  -- must be set before colorscheme
require('config.plugins')

local notify = require('mini.notify')
-- Async check for remote config updates so startup isn't blocked by the network.
vim.api.nvim_create_autocmd('VimEnter', {
  once = true,
  callback = function()
    vim.system(
      { 'git', '-C', config_dir, 'pull', '--dry-run' },
      { text = true },
      function(out)
        if (out.stdout or '') ~= '' or (out.stderr or '') ~= '' then
          vim.schedule(function()
            local notificationId = notify.add('Remote config updated', 'WARN', 'Comment')
            vim.defer_fn(function() notify.remove(notificationId) end, 1000)
          end)
        end
      end
    )
  end,
})

-- Basic settings --
vim.o.number = true            -- Show line numbers
vim.o.relativenumber = true    -- Use relative line numbers
vim.g.mapleader = ' '          -- Set space as leader key
vim.g.maplocalleader = ' '     -- Local leader (for buffer-local mappings)
vim.o.undofile = true
vim.o.clipboard = 'unnamedplus'
vim.o.title = true
vim.o.ruler = false
vim.o.showmode = false
vim.o.showcmd = false
vim.o.numberwidth = 4
vim.o.smarttab = true
vim.o.expandtab = true         -- spaces, not tabs
vim.o.shiftwidth = 2
vim.o.tabstop = 8              -- make stray tabs visually obvious

-- See `:help 'list'` and `:help 'listchars'`
vim.opt.list = true
vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }

vim.opt.cursorline = true
vim.opt.scrolloff = 10

-- keymaps --
vim.keymap.set('n', '<leader>ed', function()
  MiniFiles.open(vim.api.nvim_buf_get_name(0))
end, { desc = 'mini.files' })
vim.keymap.set('n', '<leader>ei', '<Cmd>edit $MYVIMRC<CR>', { desc = 'init.lua' })
