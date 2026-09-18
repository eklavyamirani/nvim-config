# Language servers

## Installing servers

Every enabled server is listed in `lua/config/lsp_servers.lua`, with where it installs
under `stdpath('data')` and how to install it. Install or update all of them with:

```sh
make deps                          # macOS/Linux
nvim -l scripts/install_deps.lua   # any platform, including Windows
```

Pass server names (e.g. `nvim -l scripts/install_deps.lua csharp_ls`) to install
only some. Prerequisites must already be on PATH: Python 3 for BasedPyright and the
.NET 10 SDK for csharp-ls. Each server falls back to its executable on PATH when
its installation is absent.

To add a server, create `lsp/<name>.lua`, register it with install steps in
`lua/config/lsp_servers.lua` (servers are enabled from there), and add its expected
install path to `tests/lsp_servers.lua`, which fails when these disagree.

## Python

Python uses Neovim's native `vim.lsp.config` / `vim.lsp.enable` discovery with
BasedPyright. No additional Neovim plugin or completion engine is required.

The server is installed in `~/.local/share/nvim/python-lsp`, independently of
project dependencies. `make deps` runs the equivalent of:

```sh
python3 -m venv ~/.local/share/nvim/python-lsp
~/.local/share/nvim/python-lsp/bin/python -m pip install -r lsp/requirements.txt
```

The config uses that installation when present, otherwise it looks for
`basedpyright-langserver` on PATH. With a custom `XDG_DATA_HOME`, put the virtual
environment in Neovim's `stdpath('data') .. '/python-lsp'` instead.

Launch the chosen checkout with `bin/nvim-config`; see
[WORKTREES.md](../WORKTREES.md). Roots are
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
| `<C-x><C-o>` in Insert mode | Manually request LSP completion |
| `<C-n>` / `<C-p>` with completion menu open | Next/previous suggestion |
| `<C-y>` / `<C-e>` with completion menu open | Accept/dismiss suggestion |
| `<leader>ld` | Diagnostic details |
| `[d` / `]d` | Previous/next diagnostic (native defaults) |
| `<C-t>` | Return after a definition jump |

Native LSP suggestions appear automatically on server-advertised trigger
characters, such as `.`, in Python and C# buffers with an attached server.
Use `<C-x><C-o>` in Insert mode to request suggestions at other times.
Nothing is selected automatically; choose a suggestion and accept with `<C-y>`.
The selected suggestion's documentation appears in a popup when available.

Diagnostics use basic type checking and no sign-column glyphs. Tagged hint
dimming, automatic f-string changes, and automatic baseline-file updates are
disabled. There is no format-on-save or automatic code-action hook.

LSP automatically attaches to real Python file buffers. In Diffview's committed
Python panes, `gd`, `K`, and `grr` query a separate BasedPyright server using a temporary
Git archive of that pane's commit. The first request prepares the source and
starts the server asynchronously. Each revision has its own source directory;
the reviewed files are never presented as working-tree documents to the server.

`gd` selects the target file and revision pane in the current Diffview tab.
Unchanged files open in a reusable read-only source pane in that tab (`q` closes
it). `grr` finds references (including the declaration) at that pane's commit;
multiple matches appear in a picker with file, line, and column. Selecting a
match uses the same revision-aware navigation as `gd`. `Ctrl-t` returns to the
position before a definition or reference jump. This bridge
provides definition, hover, and reference requests; it does not attach diagnostics, rename,
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

## C#/.NET

C# uses [csharp-ls](https://github.com/razzmatazz/csharp-language-server), a
Roslyn-based server, through native Neovim LSP. No additional Neovim plugin is
needed. Install the [.NET 10 SDK or later](https://dotnet.microsoft.com/download)
(required by the server), plus any SDK required by your project's `global.json`.
Then run `make deps`, which installs the server separately from project
dependencies, equivalent to:

```sh
dotnet tool install --tool-path ~/.local/share/nvim/csharp-lsp csharp-ls --version 0.27.0
```

With a custom `XDG_DATA_HOME`, use Neovim's `stdpath('data') .. '/csharp-lsp'`.
The config falls back to `csharp-ls` on PATH if this installation is absent.
The .NET runtime must also be discoverable; SDK managers may require setting
`DOTNET_ROOT` to their SDK installation directory before launching Neovim.

Run `dotnet restore` in your solution/project, then open a `.cs` file with this
checkout's `bin/nvim-config`. The server starts at the nearest ancestor containing
`.sln` or `.slnx`, falling back to `.csproj`. Loose C# files without a project do
not start the server. For multiple solutions in one directory, set
`vim.lsp.config('csharp_ls', { settings = { csharp = { solutionPathOverride = 'MyApp.slnx' } } })`
before opening C# files.

The navigation, diagnostic, and completion keys in the Python table also apply
to C#. Native defaults provide `grn` for rename and `gra` for code actions;
`:lua vim.lsp.buf.format()` formats on request. No format-on-save is configured.
Diagnostics have no sign-column glyphs. Server defaults preserve `.editorconfig`
formatting and leave optional Roslyn analyzers disabled. C# Treesitter uses the
`c_sharp` parser with Neovim's `cs` filetype.

Use `:checkhealth vim.lsp` to diagnose attachment failures. Build and test with
`:!dotnet build` and `:!dotnet test` from the solution directory, or use a terminal.
This setup covers C# project files; it does not configure F#, Razor, or debugging.
Commit-specific Diffview LSP navigation remains Python-only.

Run configuration/root-discovery checks without the SDK:

```sh
bin/nvim-config --headless -u init.lua -c "lua dofile('tests/csharp_lsp.lua')"
bin/nvim-config --headless -u NONE -c "lua dofile('tests/lsp_servers.lua')"
```
