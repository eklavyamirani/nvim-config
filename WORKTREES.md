# Isolated configuration worktrees

The installed checkout at `~/.config/nvim` is on `main`, which includes Python
LSP and revision-aware Diffview navigation from PR #2. Ordinary `nvim` uses this
configuration. The ongoing review work remains on `review/workflow`, which now
includes `main` and the previously tested integration.

| Directory under `~/.config/nvim-worktrees/` | Branch | Purpose |
| --- | --- | --- |
| `review` | `review/workflow` | Review groups, explanations, and reading fixes, with Python LSP from main |
| `review-python` | `test/review-python` | Retained for the existing Neovim session; use `review` for new sessions |

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

Make review changes in `review/workflow`. To incorporate future updates from
`main`:

```sh
git -C ~/.config/nvim fetch origin
git -C ~/.config/nvim merge --ff-only origin/main
git -C ~/.config/nvim-worktrees/review merge main
```

Restart Neovim after updating its configuration. The separate `python-lsp`
worktree and `feat/python-lsp` branch were retired after the PR merged.
`review-python` was fast-forwarded during reconciliation to preserve its running
session's config path; it is no longer a separate integration workflow. Once
that session is closed, the clean worktree and its merged branch can be removed:

```sh
git -C ~/.config/nvim worktree remove ~/.config/nvim-worktrees/review-python
git -C ~/.config/nvim branch -d test/review-python
```

Within a committed Python Diffview pane, `gd` navigates to the definition at
that revision, `K` shows hover information, and `Ctrl-t` returns to the previous
position. See `lsp/README.md` for installation, shortcuts, and limitations.
