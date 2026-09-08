# Isolated configuration worktrees

The installed checkout at `~/.config/nvim` remains on `main`. The staged review
work was preserved in commit `0a3495a` on `review/workflow` before moving it to
a linked worktree.

| Directory under `~/.config/nvim-worktrees/` | Branch | Purpose |
| --- | --- | --- |
| `review` | `review/workflow` | Review groups, explanations, and reading fixes |
| `python-lsp` | `feat/python-lsp` | Native Python LSP configuration |
| `review-python` | `test/review-python` | Both branches merged for testing |

Start the combined configuration from the project you want to review:

```sh
cd ~/repositories/selfhost-v2
~/.config/nvim-worktrees/review-python/bin/nvim-config
```

Use the corresponding launcher's path to run either branch independently.
Each launcher points `XDG_CONFIG_HOME` to a private, ignored profile symlink
inside that worktree. Config modules and the plugin lockfile therefore come
from that worktree. Installed plugins, cache, and private review state remain
shared, so the saved selfhost-v2 reading route remains available through `ga`.
Plugin updates can affect this shared installation.

The combined branch is a test integration branch. Make review changes in
`review/workflow`, make LSP changes in `feat/python-lsp`, commit them there, then
update the combined worktree:

```sh
git -C ~/.config/nvim-worktrees/review-python merge review/workflow
git -C ~/.config/nvim-worktrees/review-python merge feat/python-lsp
```

Restart the test Neovim process after updating its configuration. Neither merge
changes `main`. Ordinary `nvim` continues to use the installed `main` checkout.

From a committed Diffview snapshot, `Ctrl-w gf` opens the working-tree version
in a new tab. Python LSP operates on that real project file. It may differ from
the reviewed revision; historical Diffview buffers retain their original
contents. `gT` returns to the diff tab. See `lsp/README.md` on the LSP or combined
branch for server installation and shortcuts.
