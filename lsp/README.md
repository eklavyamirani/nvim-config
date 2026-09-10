# Python LSP

Python uses Neovim's native `vim.lsp.config` / `vim.lsp.enable` discovery with
BasedPyright. No additional Neovim plugin or completion engine is required.

The server is installed in `~/.local/share/nvim/python-lsp`, independently of
project dependencies. Reproduce that installation from this worktree:

```sh
python3 -m venv ~/.local/share/nvim/python-lsp
~/.local/share/nvim/python-lsp/bin/python -m pip install -r lsp/requirements.txt
```

The config uses that installation when present, otherwise it looks for
`basedpyright-langserver` on PATH. With a custom `XDG_DATA_HOME`, put the virtual
environment in Neovim's `stdpath('data') .. '/python-lsp'` instead.

Python LSP is included in `main`. For ongoing review changes, launch the `review`
worktree with `bin/nvim-config`; see [WORKTREES.md](../WORKTREES.md). Roots are
discovered from Python project markers, including `requirements.txt`, before
falling back to `.git`. The server's tool environment is separate from the Python interpreter used by the
project; activate the project's virtual environment before launching when it
needs one. Missing third-party packages can still produce import diagnostics.

| Key | Action |
| --- | --- |
| `K` | Hover/type documentation (native default) |
| `gd` | Go to definition |
| `grr` | Find references (native default) |
| `<C-s>` in Insert mode | Signature help (native default) |
| `<C-x><C-o>` in Insert mode | Native omnifunc completion |
| `<leader>ld` | Diagnostic details |
| `[d` / `]d` | Previous/next diagnostic (native defaults) |
| `<C-t>` | Return after a definition jump |

Diagnostics use basic type checking and no sign-column glyphs. Tagged hint
dimming, automatic f-string changes, and automatic baseline-file updates are
disabled. There is no format-on-save or automatic code-action hook.

LSP automatically attaches to real Python file buffers. In Diffview's committed
Python panes, `gd` and `K` query a separate BasedPyright server using a temporary
Git archive of that pane's commit. The first request prepares the source and
starts the server asynchronously. Each revision has its own source directory;
the reviewed files are never presented as working-tree documents to the server.

`gd` selects the target file and revision pane in the current Diffview tab.
Unchanged files open in a reusable read-only source pane in that tab (`q` closes
it). `Ctrl-t` returns to the previous definition jump's position. This bridge
provides definition and hover requests; it does not attach diagnostics, rename,
or completion to Diffview buffers. Normal files retain the full native LSP setup.

This currently supports committed Git source, including either comparison side.
Index/conflict/custom snapshots, definitions outside the archived repository,
submodule contents, and files excluded by Git's `export-ignore` are not supported.
The archive does not reproduce historical installed Python dependencies. Requests
are cancelled if the displayed source differs from its archived copy. Temporary
archives are session-local and disappear with Neovim's temporary directory.

For working-tree navigation, Diffview's native `Ctrl-w gf` opens the checked-out
version in a new tab; `gT` returns to the comparison. That file may differ from
the reviewed commit.

References: [Neovim LSP](https://neovim.io/doc/user/lsp/),
[BasedPyright installation](https://docs.basedpyright.com/latest/installation/command-line-and-language-server/),
[server settings](https://docs.basedpyright.com/latest/configuration/language-server-settings/).
