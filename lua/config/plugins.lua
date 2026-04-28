-- Plugin management with the built-in vim.pack (Neovim 0.12+).
-- Plugins are cloned to ~/.local/share/nvim/site/pack/core/opt/<name>
-- on first launch (synchronously) and loaded automatically.
vim.pack.add({
  { src = 'https://github.com/nvim-lualine/lualine.nvim' },
  { src = 'https://github.com/nvim-tree/nvim-web-devicons' },
  { src = 'https://github.com/nvim-mini/mini.files',    version = 'stable' },
  { src = 'https://github.com/nvim-mini/mini.notify',   version = 'stable' },
  { src = 'https://github.com/catppuccin/nvim',         name = 'catppuccin' },
  { src = 'https://github.com/folke/which-key.nvim' },
  { src = 'https://github.com/nvim-treesitter/nvim-treesitter' },
  { src = 'https://github.com/mfussenegger/nvim-lint' },
  { src = 'https://github.com/windwp/nvim-autopairs' },
  { src = 'https://github.com/lewis6991/gitsigns.nvim' },
  { src = 'https://github.com/numToStr/Comment.nvim' },
  { src = 'https://github.com/catgoose/nvim-colorizer.lua' },
  { src = 'https://github.com/MeanderingProgrammer/render-markdown.nvim' },
  { src = 'https://github.com/nvim-lua/plenary.nvim' },
  { src = 'https://github.com/eklavyamirani/code-review.nvim' },
  { src = 'https://github.com/ibhagwan/fzf-lua' },
})

-- Helper for plugins whose only setup is `require('x').setup()`.
local function setup(name, opts)
  local ok, mod = pcall(require, name)
  if not ok then
    vim.notify('Failed to load ' .. name, vim.log.levels.WARN)
    return
  end
  if type(mod.setup) == 'function' then mod.setup(opts or {}) end
end

setup('mini.files')
setup('mini.notify')
setup('nvim-autopairs')
setup('lualine')
setup('which-key')
setup('colorizer')
setup('render-markdown', {
  heading = {
    sign = false,        -- no sign-column glyph
    icons = {},          -- keep raw "#", "##", "###" instead of nerd-font icons
    width = 'block',     -- don't stretch heading background across the window
    backgrounds = {},    -- no background highlight on headings
    -- Per-level border. Only h1 gets a horizontal rule above and below for a
    -- strong "major section" feel; h2-h6 stay distinguished by foreground
    -- color alone (defaults).
    border = { true, false, false, false, false, false },
    border_virtual = true,  -- render via virtual lines; don't require blank
                            -- lines around the heading in the source file.
    above = '═',
    below = '═',
  },
  code = {
    enabled = false,     -- no decoration; treesitter still syntax-highlights
                         -- the contents of fenced ```lang blocks via injection
  },
  bullet = {
    icons = { '•', '◦', '▪', '▫' },  -- plain unicode bullets per nesting level
  },
  -- dash, quote, checkbox, table all keep defaults — they're already low-key.
})
setup('code-review')
setup('fzf-lua')

-- Treesitter: highlight + indent for installed parsers.
local ok_ts, ts = pcall(require, 'nvim-treesitter.configs')
if ok_ts then
  ts.setup({
    ensure_installed = { 'lua', 'vim', 'vimdoc', 'markdown', 'markdown_inline', 'bash', 'json', 'yaml' },
    auto_install = true,
    highlight = { enable = true },
    indent = { enable = true },
  })
end

-- Colorscheme.
pcall(vim.cmd.colorscheme, 'catppuccin')

-- gitsigns: set buffer-local hunk-navigation/staging keymaps when attached.
setup('gitsigns', {
  on_attach = function(buf)
    local gs = require('gitsigns')
    local map = function(lhs, rhs, desc)
      vim.keymap.set('n', lhs, rhs, { buffer = buf, desc = desc })
    end
    map(']c', function() gs.nav_hunk('next') end, 'Next hunk')
    map('[c', function() gs.nav_hunk('prev') end, 'Prev hunk')
    map('<leader>hp', gs.preview_hunk, 'Preview hunk')
    map('<leader>hs', gs.stage_hunk,   'Stage hunk')
    map('<leader>hr', gs.reset_hunk,   'Reset hunk')
    map('<leader>hb', function() gs.blame_line({ full = true }) end, 'Blame line')
    map('<leader>hd', gs.diffthis, 'Diff this')
  end,
})

setup('Comment', {
  padding = true,
  sticky = true,
  ignore = nil,
  toggler = {
    line = 'gcc',
    block = 'gbc',
  },
  -- opleader is for operator-pending motions, e.g. `gcap` to comment a paragraph.
  opleader = {
    line = 'gc',
    block = 'gb',
  },
  extra = {
    above = 'gcO',
    below = 'gco',
    eol = 'gcA',
  },
  mappings = {
    basic = true,
    extra = true,
  },
})

-- nvim-lint: configure linters per filetype and trigger on save / read.
local ok_lint, lint = pcall(require, 'lint')
if ok_lint then
  lint.linters_by_ft = {
    lua = { 'luacheck' },
    sh = { 'shellcheck' },
    bash = { 'shellcheck' },
    markdown = { 'markdownlint' },
  }
  vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufReadPost' }, {
    callback = function() lint.try_lint() end,
  })
end

-- fzf-lua keymaps.
local ok_fzf, fzf = pcall(require, 'fzf-lua')
if ok_fzf then
  vim.keymap.set('n', '<leader>ff', fzf.files,         { desc = 'Find files' })
  vim.keymap.set('n', '<leader>fg', fzf.live_grep,     { desc = 'Live grep' })
  vim.keymap.set('n', '<leader>fb', fzf.buffers,       { desc = 'Buffers' })
  vim.keymap.set('n', '<leader>fh', fzf.help_tags,     { desc = 'Help tags' })
  vim.keymap.set('n', '<leader>fr', fzf.resume,        { desc = 'Resume last picker' })
  vim.keymap.set('n', '<leader>f/', fzf.lgrep_curbuf,  { desc = 'Grep current buffer' })
end
