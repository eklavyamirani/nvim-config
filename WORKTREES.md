# Isolated configuration worktrees

For the development handoff, completed features, and remaining design questions,
start with [README.md](README.md). This file describes the local worktree setup
after PR #6; use `git worktree list` to check whether it has changed.

The installed checkout at `~/.config/nvim` is on `main`, which includes Python
LSP from PR #2 and the review workflow from PR #6. Ordinary `nvim` includes the
grouped file trees, reading fixes, and persistent question/answer threads.
The next round of review work is on `review/next`, created from the merged `main`.

| Directory under `~/.config/nvim-worktrees/` | Branch or revision | Purpose |
| --- | --- | --- |
| `review` | `review/next` | Next review changes, starting from merged main |
| `review-python` | Detached at `123deb7` (PR #6) | Legacy config path; use `review` for new work |

Start the review configuration from the project you want to review:

```sh
cd ~/repositories/selfhost-v2
~/.config/nvim-worktrees/review/bin/nvim-config
```

Each launcher points `XDG_CONFIG_HOME` to a private, ignored profile symlink
inside that worktree. Config modules and the plugin lockfile therefore come
from that worktree. Installed plugins, cache, and private review state remain
shared, so the saved selfhost-v2 reading route remains available through `ga`.
Plugin updates can affect this shared installation.

Using `nvim -u /path/to/worktree/init.lua` alone does not select the worktree's
Lua modules or lockfile. Use its `bin/nvim-config` launcher. Inside Neovim,
`:echo stdpath('config')` identifies the configuration path in use. The legacy
`review-python` launcher stays on the merged checkpoint and will not pick up
changes made on `review/next`.

Make review changes in `review/next`. To incorporate future updates from
`main`:

```sh
git -C ~/.config/nvim fetch origin
git -C ~/.config/nvim merge --ff-only origin/main
git -C ~/.config/nvim-worktrees/review merge main
```

Restart Neovim after updating its configuration. The merged development branches
were retired. The pre-squash review history is preserved locally by the tag
`archive/review-pr6`. The separate `python-lsp` worktree was already removed.
`review-python` retains the merged code at a detached HEAD so the running
session's config path remains available. It does not track new development.
Check that no session still uses that configuration path before removal, and
check for local changes first. Once unused and clean, remove it without force:

```sh
git -C ~/.config/nvim-worktrees/review-python status --short
git -C ~/.config/nvim worktree remove ~/.config/nvim-worktrees/review-python
```

Within a committed Python Diffview pane, `gd` navigates to the definition at
that revision, `grr` finds references, `K` shows hover information, and `Ctrl-t` returns to the previous
position. See [lsp/README.md](lsp/README.md) for installation, shortcuts, and
limitations.
