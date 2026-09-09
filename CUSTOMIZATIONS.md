# Customization record

> Generated from the executable `tests/customizations.json` manifest by `make customizations`;
> do not edit by hand. CI fails when configuration, tests, and this record drift apart.

## Plugins

| Repository | Runtime module | Declared at |
| --- | --- | --- |
| `nvim-lualine/lualine.nvim` | `lualine` | `lua/config/plugins.lua:5` |
| `nvim-tree/nvim-web-devicons` | `nvim-web-devicons` | `lua/config/plugins.lua:6` |
| `nvim-mini/mini.files` | `mini.files` | `lua/config/plugins.lua:7` |
| `nvim-mini/mini.notify` | `mini.notify` | `lua/config/plugins.lua:8` |
| `catppuccin/nvim` | `catppuccin` | `lua/config/plugins.lua:9` |
| `folke/which-key.nvim` | `which-key` | `lua/config/plugins.lua:10` |
| `nvim-treesitter/nvim-treesitter` | `nvim-treesitter` | `lua/config/plugins.lua:11` |
| `mfussenegger/nvim-lint` | `lint` | `lua/config/plugins.lua:12` |
| `windwp/nvim-autopairs` | `nvim-autopairs` | `lua/config/plugins.lua:13` |
| `lewis6991/gitsigns.nvim` | `gitsigns` | `lua/config/plugins.lua:14` |
| `numToStr/Comment.nvim` | `Comment` | `lua/config/plugins.lua:15` |
| `catgoose/nvim-colorizer.lua` | `colorizer` | `lua/config/plugins.lua:16` |
| `MeanderingProgrammer/render-markdown.nvim` | `render-markdown` | `lua/config/plugins.lua:17` |
| `nvim-lua/plenary.nvim` | `plenary` | `lua/config/plugins.lua:18` |
| `eklavyamirani/code-review.nvim` | `code-review` | `lua/config/plugins.lua:19` |
| `ibhagwan/fzf-lua` | `fzf-lua` | `lua/config/plugins.lua:20` |
| `sindrets/diffview.nvim` | `diffview` | `lua/config/plugins.lua:21` |

## Editor and global settings

| Setting | Configured value | Declared at |
| --- | --- | --- |
| `termguicolors` | `true` | `init.lua:5` |
| `mapleader` | `' '` | `init.lua:9` |
| `maplocalleader` | `' '` | `init.lua:10` |
| `number` | `true` | `init.lua:34` |
| `relativenumber` | `true` | `init.lua:35` |
| `undofile` | `true` | `init.lua:36` |
| `clipboard` | `'unnamedplus'` | `init.lua:37` |
| `title` | `true` | `init.lua:38` |
| `ruler` | `false` | `init.lua:39` |
| `showmode` | `false` | `init.lua:40` |
| `showcmd` | `false` | `init.lua:41` |
| `numberwidth` | `4` | `init.lua:42` |
| `smarttab` | `true` | `init.lua:43` |
| `expandtab` | `true` | `init.lua:44` |
| `shiftwidth` | `2` | `init.lua:45` |
| `tabstop` | `8` | `init.lua:46` |
| `list` | `true` | `init.lua:49` |
| `listchars` | `{ tab = '» ', trail = '·', nbsp = '␣' }` | `init.lua:50` |
| `cursorline` | `true` | `init.lua:51` |
| `scrolloff` | `10` | `init.lua:53` |

## Keymaps

Mappings with literal modes and keys are listed; generated mappings are exercised by their feature tests.

| Mode | Key | Purpose | Declared at |
| --- | --- | --- | --- |
| `n` | `<leader>ed` | mini.files | `init.lua:56` |
| `n` | `<leader>ei` | init.lua | `init.lua:59` |
| `n` | `<leader>?` | Open cheatsheet in a tab | `init.lua:60` |
| `n` | `<leader>ay` | AI: yank current line to clipboard | `init.lua:132` |
| `n` | `<leader>aY` | AI: yank whole buffer to clipboard | `init.lua:133` |
| `n` | `<leader>dv` | Diffview: open (working tree) | `lua/config/plugins.lua:76` |
| `n` | `<leader>dm` | Diffview: review branch vs default | generated in configuration |
| `n` | `<leader>dh` | Diffview: file history | `lua/config/plugins.lua:94` |
| `n` | `<leader>dH` | Diffview: branch history | `lua/config/plugins.lua:95` |
| `n` | `<leader>dc` | Diffview: close | `lua/config/plugins.lua:96` |
| `n` | `<leader>df` | Diffview: toggle file panel | `lua/config/plugins.lua:97` |
| `n` | `<leader>ff` | Find files | `lua/config/plugins.lua:176` |
| `n` | `<leader>fg` | Live grep | `lua/config/plugins.lua:177` |
| `n` | `<leader>fb` | Buffers | `lua/config/plugins.lua:178` |
| `n` | `<leader>fh` | Help tags | `lua/config/plugins.lua:179` |
| `n` | `<leader>fr` | Resume last picker | `lua/config/plugins.lua:180` |
| `n` | `<leader>f/` | Grep current buffer | `lua/config/plugins.lua:181` |
| `n` | `<leader>ao` | Review: organize files in Diffview panel | `lua/config/review_route.lua:539` |
| `n` | `]r` | Review: next file in panel order | `lua/config/review_route.lua:540` |
| `n` | `[r` | Review: previous file in panel order | `lua/config/review_route.lua:541` |
| `n` | `<leader>ae` | Review: explain beside the diff | generated in configuration |
| `n` | `<leader>ap` | Review: pin selected context | generated in configuration |
| `n` | `<leader>af` | Review: focus explanation | generated in configuration |
| `n` | `<leader>aq` | Review: ask a follow-up | generated in configuration |
| `n` | `<leader>an` | Review: edit pinned notes | generated in configuration |
| `n` | `<leader>ar` | Review: return to code | generated in configuration |
| `n` | `<leader>ax` | Review: close support panes | generated in configuration |
| `x` | `<leader>ay` | AI: yank selection to clipboard | `init.lua:131` |
| `x` | `<leader>ae` | Review: explain beside the diff | generated in configuration |
| `x` | `<leader>ap` | Review: pin selected context | generated in configuration |

## Automation

| Event expression | Declared at |
| --- | --- |
| `'VimEnter'` | `init.lua:15` |
| `'FileType'` | `lua/config/plugins.lua:104` |
| `{ 'BufWritePost', 'BufReadPost' }` | `lua/config/plugins.lua:168` |
| `{ 'BufLeave', 'VimLeavePre' }` | `lua/config/review_context.lua:316` |
| `'VimLeavePre'` | `lua/config/review_context.lua:317` |
| `'User'` | `lua/config/review_route.lua:548` |
| `'VimLeavePre'` | `lua/config/review_route.lua:550` |

## Behavioral coverage

| Area | Executable record |
| --- | --- |
| Startup, options, mappings, plugins, commands, autocmds, and AI clipboard formatting | `tests/config.lua` |
| Explanation panes, exact selections, private notes, request ordering, and recovery | `tests/review_context.lua` |
| Committed-diff ordering, marks, persistence, migration, and assistant routing | `tests/review_route.lua` |
| Tree/list rendering, nested marks, folding, and navigation | `tests/review_tree.lua` |
| Working tree, staged changes, staging, invalidation, and persistence | `tests/review_worktree.lua` |
| Full-init default-branch discovery and Diffview integration | `tests/review_startup.lua` |
