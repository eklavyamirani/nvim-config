# Configuration worktrees

Read [README.md](README.md) for the configuration's behavior, source map, and
validation commands, and [AGENTS.md](AGENTS.md) before making changes.

## Select a checkout

The local installation and development checkouts have different roles:

| Path | Purpose |
| --- | --- |
| `~/.config/nvim` | Installed configuration used by ordinary `nvim` |
| `~/.config/nvim-worktrees/` | Development checkouts for configuration changes |
| Other paths shown by `git worktree list` | Additional checkouts; inspect their branch and usage before changing them |

Branches and revisions can change independently of these paths. Inspect live
Git state instead of assuming which branch a checkout contains:

```sh
git worktree list
git status --short --branch
```

Run these from the checkout where you intend to work. Preserve existing changes
and use the development checkout unless the user's task calls for another one.
Do not switch or update the installed checkout as a side effect of testing.

## Run the selected configuration

From the project you want to edit or review, launch the development configuration:

```sh
cd /path/to/project
~/.config/nvim-worktrees/<branch>/bin/nvim-config
```

For another checkout, use that checkout's `bin/nvim-config`. The launcher points
`XDG_CONFIG_HOME` to an ignored `.nvim-profile/nvim` symlink inside its checkout.
Lua modules and the plugin lockfile therefore come from the selected checkout.
Using `nvim -u /path/to/worktree/init.lua` alone does not select that worktree's
Lua modules or lockfile.

Inside Neovim, `:echo stdpath('config')` identifies the configuration path in use.
Resolve the profile symlink if needed to identify its checkout. Check this when
the observed behavior differs from the code you are editing. An existing session
keeps its loaded configuration; restart using the intended launcher after updates.

The launcher leaves data, cache, and state locations shared between checkouts.
Plugin updates can affect other sessions, and saved review routes and notes
remain available across launchers. Tests and development should preserve that
private state. Use the validation commands in [README.md](README.md) from the
chosen checkout.

## Maintain worktrees

Before synchronizing a branch, inspect its status, upstream, and divergence:

```sh
git fetch origin
git status --short --branch
git log --oneline --left-right HEAD...origin/main
```

Integrate updates into the intended development branch according to the task.
When updating the installed configuration, first confirm that its checkout is
clean and on `main`; `git merge --ff-only origin/main` then updates it without
creating a merge commit. Restart Neovim to load the updated configuration.

Additional worktrees may still be used by running Neovim sessions. Before removing
one, confirm it is unused and check its local changes. Once unused and clean,
remove it without force from another checkout:

```sh
git -C /path/to/unused-worktree status --short --branch
git worktree remove /path/to/unused-worktree
```
