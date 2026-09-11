# Neovim configuration

This configuration uses Neovim 0.12+, native `vim.pack`, and a committed plugin
lockfile. It includes Diffview review tools, persistent code-explanation threads,
and native Python (BasedPyright) and C# (csharp-ls) LSP. CI targets Neovim 0.12.5 and nightly.

## Start a development session

Read [AGENTS.md](AGENTS.md) for the owner's preferences and
[WORKTREES.md](WORKTREES.md) for selecting and running a configuration checkout.
Before editing, inspect the actual checkout and any existing changes:

```sh
pwd
git status --short --branch
git worktree list
```

Use the user's current feedback to determine the task. The installed configuration
and the development checkout can differ; verify which one the user's Neovim
session loads before diagnosing behavior. Run the chosen checkout's
`bin/nvim-config` from the project being edited or reviewed, and restart Neovim
after changing the configuration.

## Editor and review workflow

The leader key is Space. See the [shortcut guide](cheatsheet.md) for most commonly used editor,
file navigation, Git review, notifications, and assistant commands.

Diffview uses its existing file panel for default, AI, and custom review orders.
AI groups have directory trees and review questions; files can be marked todo,
done, or later. Panel paths wrap, added files use a single code pane, and file
navigation preserves reading positions. In the file panel, `ga` restores the
saved AI order (or generates one if absent) and `go` generates or replaces it.

`<leader>ae` explains the current line or visual selection beside the code.
`<leader>aa` starts a specific question about that code. `<leader>aq` appends a
follow-up and sends the earlier conversation as context. A new `ae` or `aa`
starts a fresh thread; `:ReviewContext` restores the saved thread after restarting.
Pinned notes supply reusable context. The assistant backend defaults to an
authenticated Copilot CLI; Claude Code is configurable. See the
[assistant workflow](cheatsheet.md#ai-cli-bridge-clipboard) for setup and controls.

Python files use native LSP with BasedPyright. In committed Python Diffview
panes, `gd`, `K`, and `grr` query a temporary archive of the displayed commit for
definitions, hover information, and references. Jumps stay in the Diffview tab;
unchanged files open read-only, and `Ctrl-t` returns to the source position.
The server is installed separately from plugins and project dependencies; see
the [Python LSP guide](lsp/README.md) for installation and supported snapshots.

C# files use native LSP with csharp-ls and Treesitter highlighting. See the
[C#/.NET setup guide](lsp/README.md#cnet) for SDK/server installation, project
roots, and commands.

## Current limitations

AI grouping uses file metadata and sampled diffs. It has no interaction for
capturing the reviewer's goals before generating groups, and Python LSP analysis
is not supplied to the grouping request. Explanations use captured code,
surrounding lines, pinned notes, and conversation context; they do not execute
the reviewed code. The support panes handle ordinary files and Diffview, but
are not adapted to the separate CodeReview plugin's custom buffers.

Commit-specific LSP navigation supports Git commits on either comparison side.
Index/conflict snapshots and historical installed dependencies are not reproduced.
Normal Python file buffers retain the native LSP setup.

## State and source locations

Routes, pinned notes, and the latest conversation are stored outside the repo
under `stdpath('state')/review-context/<repository-id>/`. Find the state root with
`:echo stdpath('state')`. Preserve existing saved routes and notes when testing;
do not copy private conversation contents or review artifacts into repository
documentation. Tests use temporary repositories for their review data.

| File | Responsibility |
| --- | --- |
| `init.lua` | Editor settings, global mappings, native LSP activation |
| `lua/config/plugins.lua` | Plugin declarations/setup, Diffview options, notification history |
| `lua/config/review_route.lua` | Review groups, ordering, marks, trees, and reading positions |
| `lua/config/review_context.lua` | Captured source, assistant requests, conversation panes, private persistence |
| `lua/config/diffview_lsp.lua` | Commit-specific Python definition, hover, and references |
| `lsp/csharp_ls.lua` | Native C# server configuration |
| `lsp/basedpyright.lua` | Native Python server configuration |
| `nvim-pack-lock.json` | Committed plugin versions |
| `bin/nvim-config` | Launch Neovim with this checkout's configuration |
| `tests/config_spec.json` | Declared configuration inventory checked by `scripts/check_config.py` |
| `.github/workflows/ci.yml` | CI environment and validation jobs |

## Validation

From the chosen checkout, use its launcher so Neovim loads that worktree's Lua
modules and lockfile:

```sh
bin/nvim-config --headless -u init.lua +qa
make test NVIM=bin/nvim-config
```

`make test` checks the inventory, loaded editor settings, and review behavior,
including grouping, selection capture, full follow-up history, persistence,
errors, navigation, and notification copying. Keep the inventory in sync when
adding mappings or autocmd events. A startup error or unexpected stderr is a
failure.

For Python LSP or Diffview navigation changes, install the server as described
in [lsp/README.md](lsp/README.md), then also run:

```sh
bin/nvim-config --headless -u init.lua -c "lua dofile('tests/python_lsp.lua')"
bin/nvim-config --headless -u init.lua -c "lua dofile('tests/diffview_lsp.lua')"
```

These two LSP tests are separate from `make test` and are not run by CI.
