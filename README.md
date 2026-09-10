# Neovim configuration

This configuration uses Neovim 0.12+, native `vim.pack`, and a committed plugin
lockfile. It includes Diffview review tools, persistent code-explanation threads,
and native Python LSP with BasedPyright. Validation currently targets Neovim
0.12.5 locally and 0.12.5/nightly in CI.

## Start a new development session

Read [AGENTS.md](AGENTS.md) for the owner's preferences and
[WORKTREES.md](WORKTREES.md) for checkout locations and lifecycle instructions.
Continue development in this checkout:

```sh
cd ~/.config/nvim-worktrees/review
git status --short --branch
```

The current development branch is `review/next`, created from `main` after
[PR #6](https://github.com/eklavyamirani/nvim-config/pull/6) merged. The installed
checkout at `~/.config/nvim` stays on `main`. These handoff updates are on
`review/next`; copies of the docs on `main` describe the last merged checkpoint.
Verify the actual state with `git worktree list` before changing branches.

To test development changes while reviewing a project:

```sh
cd ~/repositories/selfhost-v2
~/.config/nvim-worktrees/review/bin/nvim-config
```

Ordinary `nvim` uses the installed `main` configuration and already includes
the merged review and LSP features. Restart Neovim to load configuration changes.

## Working checkpoint

- [PR #2](https://github.com/eklavyamirani/nvim-config/pull/2): native Python
  LSP and definition/hover navigation against the commit displayed in Diffview.
- [PR #3](https://github.com/eklavyamirani/nvim-config/pull/3): CI, configuration
  inventory, and checks for configuration drift.
- [PR #6](https://github.com/eklavyamirani/nvim-config/pull/6): AI review groups
  with directory trees and review questions; wrapped file-panel paths;
  single-pane additions; preserved reading positions; copyable notifications;
  direct questions and persistent follow-up threads.

The owner tested the workflow and confirmed it works well. `<leader>ae` starts
an explanation; repeated `<leader>aq` calls append user/AI messages and send
the earlier conversation as context. `<leader>aa` starts a question about the
selected code. A new `ae` or `aa` starts a fresh thread; `:ReviewContext`
restores the saved thread after restarting.

See the [shortcut guide](cheatsheet.md) for everyday use and
[Python LSP guide](lsp/README.md) for server installation and snapshot-navigation
limitations. The LSP server lives outside project dependencies; it is not
installed by `vim.pack` or by starting the editor.

## Remaining design problem

AI grouping still starts from file metadata and sampled diffs. Group titles
and questions help navigation, but they do not establish what the reviewer
wants to understand or validate. LSP currently supports Python source navigation;
its analysis is not supplied to the AI grouping request.

The next design task is to define how the reviewer supplies their goals before
requesting groups. The owner wants help articulating their needs, rather than
having the assistant's suggested goals stand in for their own. Capture intended
behaviors, priorities, unfamiliar language concepts, and correctness/security
questions, then use that context to propose a reading route. Agree on the
problem statement and a small interaction to try before expanding the grouping
implementation. This goal-capture flow is not implemented yet.

The motivating trial is the reconciler change in `selfhost-v2`:

- The reconciler is critical. Focus on its self-update loop and how application
  updates are applied, including failures, edge cases, and security.
- Python is unfamiliar to the reviewer; explain syntax when it blocks their
  understanding of behavior.
- Application manifests, schemas, and configuration are high priority.
  Ansible setup is medium priority; Terraform setup is lower priority.

A tailored route and review notes were prepared privately for that trial.
`ga` reuses the saved AI route; `go` generates a replacement using the current
generic grouping prompt. Preserve the trial when investigating a goal-driven
workflow. It is a reading aid, not a completed correctness or security audit.

## State and source locations

Routes, pinned notes, and the latest conversation are stored outside the repo
under `stdpath('state')/review-context/<repository-id>/`. The trial's supporting
brief and guide are in `reconciler-goal-trial/` within its repository state
directory. Find the state root with `:echo stdpath('state')`. Do not copy private
conversation contents or review artifacts into repository documentation.

| File | Responsibility |
| --- | --- |
| `init.lua` | Editor settings, global mappings, native LSP activation |
| `lua/config/plugins.lua` | Plugin declarations/setup, Diffview options, notification history |
| `lua/config/review_route.lua` | Review groups, ordering, marks, trees, and reading positions |
| `lua/config/review_context.lua` | Captured source, assistant requests, conversation panes, private persistence |
| `lua/config/diffview_lsp.lua` | Commit-specific Python definition, hover, and references |
| `lsp/basedpyright.lua` | Native Python server configuration |
| `tests/config_spec.json` | Declared configuration inventory checked by `scripts/check_config.py` |

## Validation

From the development checkout, use its launcher so Neovim loads that worktree's
Lua modules and lockfile:

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

These two LSP tests are separate from `make test`. The merged checkpoint passed
the full review suite, startup checks, and the relevant LSP tests.
