# AGENTS.md

Guidance for AI assistants working in this Neovim config repo. Read this before
proposing changes — it captures the owner's preferences and mental model.

## High-level preferences

- **Prefer built-in / native solutions over third-party when comparable.**
  - Plugin manager: `vim.pack` (nvim 0.12+ built-in) — not lazy.nvim, packer, or
    vim-plug.
  - Use other native APIs (`vim.system`, `vim.keymap.set`, `vim.uv`) over their
    `vim.fn.*` / legacy equivalents.
- **Maintained > popular.** When picking between forks, choose the actively
  maintained one even if less famous (e.g. `catgoose/nvim-colorizer.lua` over
  the unmaintained `norcalli/`).
- **Minimal, surgical changes.** Don't rewrite working code to "modernize" it
  unless asked. Fix the bug, leave the rest.
- **Keep startup fast and non-blocking.** Anything network-bound (e.g. checking
  for remote config updates) must be async via `vim.system` + autocmd, never
  blocking `vim.fn.system`.
- **Lockfiles are committed.** `nvim-pack-lock.json` lives in the repo for
  reproducible plugin versions.

## Aesthetic preferences (very important)

The owner strongly prefers **minimalist visual rendering**. When configuring
any plugin that affects appearance:

- **No background shading on text** — color foregrounds, not backgrounds. The
  one exception is inline code, where a subtle background is acceptable.
- **Keep source characters visible.** Don't replace `#`, `##`, `-`, `*`, etc.
  with nerd-font icons. The user wants to see what's actually in the file.
- **Distinction through color, not noise.** Different heading levels = different
  foreground colors. Avoid icons, tinted backgrounds, sign-column glyphs by
  default.
- **Borders only for major structural elements.** A horizontal rule above and
  below `h1` is good (it signals a major section). Don't decorate every level.
- **Virtual rendering preferred over source modification.** When a plugin offers
  a "virtual" mode that adds visual elements without touching the underlying
  file (e.g. `border_virtual = true` in render-markdown), use it.
- **If a decoration would create alignment artifacts, turn it off entirely.**
  Half-rendered things (label-with-background floating over a line without
  background) look worse than nothing. Prefer "off" to "partially on".

When in doubt, lean toward less. The owner will ask for more if needed.

## Honest tradeoffs

- **State real limitations clearly.** Neovim is a TUI — variable font sizes are
  impossible, period. Don't propose elaborate workarounds for platform limits;
  explain the limit and offer the closest approximation (e.g. heavier borders,
  or external preview tools like `markdown-preview.nvim`).
- **Flag when defaults are doing the work.** If a plugin "works out of the box,"
  say so rather than padding the config with no-op options.
- **Distinguish bugs from preferences.** Use the rubric:
  - 🔴 Real bug (will break things) — fix without asking.
  - 🟡 Worth fixing (improvement with clear payoff) — flag and propose.
  - 🟢 Nit / preference — mention briefly, don't push.

## Workflow

- **Incremental review-and-apply.** The owner prefers iterating: review →
  apply → "anything else?" → repeat. Don't dump 15 changes in one go; surface
  3–5 ranked items, apply what they pick, then continue.
- **Verify changes load cleanly** with `nvim --headless -u init.lua +qa`
  before declaring a task done. Treat non-zero exit or unexpected stderr as a
  failure.
- **Plugin changes that swap a `src=` URL** require manual handling because
  `vim.pack.add` is a no-op if the same plugin name was already added in this
  session. Use `vim.pack.del({name},{force=true})` then re-add to force the
  swap on disk.

## Project conventions

- **File layout:** `init.lua` for editor settings + keymaps; `lua/config/plugins.lua`
  for `vim.pack.add` and per-plugin `setup()`. Don't sprawl into many files
  unless the config grows substantially.
- **Plugin setup pattern:** use the local `setup(name, opts)` helper in
  `plugins.lua` for any plugin whose only configuration is `require('x').setup(...)`.
  For plugins needing more (treesitter, gitsigns `on_attach`, fzf-lua keymaps,
  nvim-lint autocmds), `pcall(require, ...)` directly.
- **Keymaps:** use `vim.keymap.set` with a `desc` field. Don't use the legacy
  `nvim_set_keymap`. Always provide `desc` so `which-key` surfaces them.
- **Comments:** only where they add clarification a reader couldn't infer
  from the code itself. No restating what the line does.
- **Leader key:** `<Space>` for both `mapleader` and `maplocalleader`.
- **Indentation:** 2-space, expandtab. `tabstop = 8` is intentional — makes
  stray hard tabs visually obvious.

## Established plugin choices

| Role            | Choice                                |
|-----------------|----------------------------------------|
| Plugin manager  | `vim.pack` (built-in)                  |
| Fuzzy finder    | `ibhagwan/fzf-lua`                     |
| File explorer   | `mini.files`                           |
| Notifications   | `mini.notify`                          |
| Statusline      | `lualine`                              |
| Colorscheme     | `catppuccin`                           |
| Git signs       | `gitsigns.nvim` (not `mini.diff`)      |
| Comments        | `Comment.nvim`                         |
| Treesitter      | `nvim-treesitter`                      |
| Linter          | `nvim-lint`                            |
| Color highlight | `catgoose/nvim-colorizer.lua` (fork)   |
| Markdown render | `render-markdown.nvim` (minimal opts)  |
| Code review     | `eklavyamirani/code-review.nvim`       |

When proposing a new plugin, justify it against what's already installed
before adding another.

## Things deliberately NOT installed (yet)

- **LSP / completion** — no LSP client or completion engine is configured. If
  proposing one, ask first; don't assume.
- **`mini.diff`** — explicitly removed in favor of gitsigns. Don't add back.
