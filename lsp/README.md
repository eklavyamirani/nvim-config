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

Launch this branch with `bin/nvim-config`, or use the combined worktree described
in `WORKTREES.md` on the review branch. Roots are discovered from Python project
markers, including `requirements.txt`, before falling back to `.git`. The
server's tool environment is separate from the Python interpreter used by the
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

LSP automatically attaches to real Python file buffers. In Diffview, the native
`Ctrl-w gf` opens the checked-out version in a new tab for LSP navigation; `gT`
returns to the comparison. A committed snapshot can differ from that file.
Historical/scratch diff buffers are not attached as working-tree documents.

References: [Neovim LSP](https://neovim.io/doc/user/lsp/),
[BasedPyright installation](https://docs.basedpyright.com/latest/installation/command-line-and-language-server/),
[server settings](https://docs.basedpyright.com/latest/configuration/language-server-settings/).
