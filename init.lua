local config_dir = vim.fn.stdpath('config')

-- Optimized module loader, improves startup performance.
vim.loader.enable()
vim.o.termguicolors = true  -- must be set before colorscheme
-- Leader must be set BEFORE plugins load, because vim.keymap.set resolves
-- <leader> at call time. Any plugin that registers a <leader>* mapping during
-- require('config.plugins') would otherwise capture the default backslash.
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '
require('config.plugins')
vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('lsp_completion', { clear = true }),
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if not client or not client:supports_method('textDocument/completion', ev.buf) then return end
    vim.lsp.completion.enable(true, client.id, ev.buf, { autotrigger = true })
  end,
})
vim.lsp.enable(vim.tbl_keys(require('config.lsp_servers').servers))
require('config.diffview_lsp').setup()

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
vim.opt.completeopt = { 'menu', 'menuone', 'noselect', 'popup' }

-- keymaps --
vim.keymap.set('n', '<leader>ed', function()
  MiniFiles.open(vim.api.nvim_buf_get_name(0))
end, { desc = 'mini.files' })
vim.keymap.set('n', '<leader>ei', '<Cmd>edit $MYVIMRC<CR>', { desc = 'init.lua' })
vim.keymap.set('n', '<leader>?', '<Cmd>tab drop ' .. config_dir .. '/cheatsheet.md<CR>',
  { desc = 'Open cheatsheet in a tab' })

-- AI clipboard bridge: format the current selection (or whole buffer) with a
-- `@path:startline-endline` header, line-numbered body, and copy to the system
-- clipboard. Paste into your AI CLI tab (claude, copilot, ...) with Cmd+V.

-- Resolve a buffer to a `@`-mentionable path plus an optional revision label.
-- Diffview buffers are named `diffview://<gitdir>/<rev>/<path>`, which no
-- assistant can open, so ask diffview's view model for the real path instead.
local function ai_location(bufnr)
  if bufnr == 0 then bufnr = vim.api.nvim_get_current_buf() end
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name:sub(1, 11) == 'diffview://' then
    local ok, lib = pcall(require, 'diffview.lib')
    local view = ok and lib.get_current_view()
    local layout = view and view.cur_layout
    for _, win in ipairs(layout and layout.windows or {}) do
      local file = win.file
      if file and file.bufnr == bufnr then
        local RevType = require('diffview.vcs.rev').RevType
        local rev
        if file.rev.type == RevType.STAGE then
          rev = file.rev.stage == 0 and 'staged' or ('stage ' .. file.rev.stage)
        elseif file.rev.type == RevType.COMMIT then
          rev = 'at ' .. file.rev:abbrev()
        elseif file.rev.type == RevType.CUSTOM then
          rev = 'custom rev'
        end
        return vim.fn.fnamemodify(file.absolute_path, ':.'), rev
      end
    end
  end
  local rel = vim.fn.fnamemodify(name, ':.')
  if rel == '' then rel = '[no name]' end
  return rel, nil
end

local function ai_yank(mode)
  local rel, rev = ai_location(0)
  local ft = vim.bo.filetype
  local start_line, end_line, lines
  if mode == 'buffer' then
    start_line, end_line = 1, vim.api.nvim_buf_line_count(0)
    lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  elseif mode == 'line' then
    start_line = vim.fn.line('.')
    end_line   = start_line + math.max(vim.v.count1 - 1, 0)
    end_line   = math.min(end_line, vim.api.nvim_buf_line_count(0))
    lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  else
    -- 'v' = anchor of current visual selection, '.' = cursor position.
    -- Using '< / '> here would be stale — those marks only update when
    -- visual mode ends, but this callback fires while still in visual mode.
    local a = vim.fn.getpos('v')[2]
    local b = vim.fn.getpos('.')[2]
    start_line = math.min(a, b)
    end_line   = math.max(a, b)
    lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  end
  local width = #tostring(end_line)
  for i, line in ipairs(lines) do
    lines[i] = ('%' .. width .. 'd  %s'):format(start_line + i - 1, line)
  end
  local header = ('@%s:%d-%d'):format(rel, start_line, end_line)
  if rev then header = header .. (' (%s)'):format(rev) end
  local body   = ('```%s\n%s\n```'):format(ft, table.concat(lines, '\n'))
  vim.fn.setreg('+', header .. '\n' .. body .. '\n')
  vim.notify(('AI: yanked %s (%d lines)'):format(header, end_line - start_line + 1))
end

vim.keymap.set('x', '<leader>ay', function() ai_yank('visual') end, { desc = 'AI: yank selection to clipboard' })
vim.keymap.set('n', '<leader>ay', function() ai_yank('line') end,   { desc = 'AI: yank current line to clipboard' })
vim.keymap.set('n', '<leader>aY', function() ai_yank('buffer') end, { desc = 'AI: yank whole buffer to clipboard' })
