# Language servers

## Installing servers

Every enabled server is listed in `lua/config/lsp_servers.lua`, with where it installs
under `stdpath('data')` and how to install it. Install or update all of them with:

```sh
make deps                                  # macOS/Linux
nvim -l scripts/install_deps.lua           # any platform, including Windows
nvim -l scripts/install_deps.lua parsers   # ... and the Treesitter parsers
```

`make deps` runs both commands. Installing the parsers up front means a session
never opens a buffer whose parser is still compiling; it needs the `tree-sitter`
CLI on PATH, and it installs the languages listed in `lua/config/treesitter.lua`.
A buffer whose parser is still missing simply opens without highlighting, and
Treesitter starts as soon as the parser lands.

Pass server names (e.g. `nvim -l scripts/install_deps.lua csharp_ls`) to install
only some. Prerequisites must already be on PATH: Python 3 for BasedPyright, the
.NET 10 SDK for csharp-ls, npm for the TypeScript and JSON servers, and `curl` plus `gzip`
(`powershell` on Windows) to unpack the rust-analyzer download. Each server falls
back to its executable on PATH when its installation is absent.

To add a parser, add it to `lua/config/treesitter.lua`, with its Neovim filetype
when the two names differ.

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
| `:DiagnosticLines` | Cycle inline diagnostic text: cursor line, whole buffer, off |
| `[d` / `]d` | Previous/next diagnostic (native defaults) |
| `<C-t>` | Return after a definition jump |

Native LSP suggestions appear automatically on server-advertised trigger
characters, such as `.`, in Python and C# buffers with an attached server.
Use `<C-x><C-o>` in Insert mode to request suggestions at other times.
Nothing is selected automatically; choose a suggestion and accept with `<C-y>`.
The selected suggestion's documentation appears in a popup when available.

Diagnostics use basic type checking and no sign-column glyphs. The message under
the cursor is rendered inline below its line (`virtual_lines` with
`current_line`), which applies to every server; `:DiagnosticLines` cycles that to
the whole buffer or off for the session. Tagged hint
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

## Rust

Rust uses [rust-analyzer](https://rust-analyzer.github.io/) through native Neovim
LSP. `make deps` downloads the pinned standalone release build — no Rust toolchain
is needed to install the server — into `~/.local/share/nvim/rust-lsp`, equivalent to:

```sh
curl -fsSL -o rust-analyzer.gz \
  https://github.com/rust-lang/rust-analyzer/releases/download/2026-11-02/rust-analyzer-<target>.gz
gzip -d rust-analyzer.gz && chmod +x rust-analyzer
```

The target triple comes from `vim.uv.os_uname()`; Windows gets the `.zip` asset,
extracted with `Expand-Archive` — not `tar`, which on Windows PATH is often Git's
GNU tar, unable to read a zip or a drive-letter path. Bump the pinned date in
`lua/config/lsp_servers.lua` to update. The config falls back to `rust-analyzer`
on PATH (e.g. a `rustup component add rust-analyzer` install) when this one is
absent.

Analysis itself still needs **Cargo and a Rust toolchain on PATH**: rust-analyzer
runs `cargo metadata` to load the project, and without it the server attaches but
reports no types or diagnostics. This repo's `mise.toml` pins the toolchain
alongside the .NET SDK, so `mise install` in this checkout provides it; otherwise
install Rust with [rustup](https://rustup.rs/).

The server starts at the nearest ancestor holding `Cargo.lock` or
`rust-project.json`, so one server covers a whole Cargo workspace rather than one
per member; a bare `Cargo.toml` and then `.git` are the fallbacks. Loose `.rs`
files outside a project get a `.git`-rooted server with no crate graph.

The navigation, diagnostic, and completion keys in the Python table also apply to
Rust, plus the native `grn` (rename) and `gra` (code actions) defaults.
`:lua vim.lsp.buf.format()` runs rustfmt on request; there is no format-on-save.
Diagnostics come from `cargo check` on save (rust-analyzer's default) with no
sign-column glyphs. Inlay hints stay off, matching the config's minimal rendering;
`:lua vim.lsp.inlay_hint.enable(true)` turns them on for a session. Build and test
with `:!cargo build` / `:!cargo test`. Procedural-macro and build-script expansion
use rust-analyzer's defaults. Commit-specific Diffview LSP navigation remains
Python-only.

## TypeScript/JavaScript

TypeScript 7 ships its language server inside the compiler binary, so `tsc --lsp
--stdio` is the whole server — no `typescript-language-server` wrapper and no
Neovim plugin. (The wrapper is incompatible with TypeScript 7 anyway: the native
compiler no longer ships `tsserver.js`.) `make deps` needs npm on PATH and
installs into `~/.local/share/nvim/typescript-lsp`, equivalent to:

```sh
npm install --prefix ~/.local/share/nvim/typescript-lsp typescript@7.0.2
```

That installation is separate from each project's own `typescript` dependency, so
editor behaviour does not change with the project's compiler version — and a
project pinned to TypeScript 5 is still analysed by the 7.x server. The config
falls back to `tsc` on PATH when the installation is absent; bump the pinned
version in `lua/config/lsp_servers.lua` to update.

Attaches to `typescript`, `typescriptreact`, `javascript`, and `javascriptreact`
buffers. The server starts at the nearest ancestor holding `tsconfig.json` or
`jsconfig.json`, falling back to `package.json` and then `.git`. Without a
`tsconfig.json`, files are analysed with default compiler options.

The navigation, diagnostic, and completion keys in the Python table also apply
here, as do the native `grn` and `gra` defaults. Treesitter uses the `typescript`,
`tsx`, and `javascript` parsers; `.tsx` files are filetype `typescriptreact` and
use the `tsx` parser. No format-on-save, no ESLint integration (nvim-lint handles
linters, and no JavaScript linter is configured), and no automatic import
organising. Commit-specific Diffview LSP navigation remains Python-only.

## JSON

JSON uses [`vscode-json-language-server`](https://github.com/hrsh7th/vscode-langservers-extracted),
the server VS Code's own JSON support is built on, through native Neovim LSP. No
Neovim plugin is involved. `make deps` needs npm on PATH and installs into
`~/.local/share/nvim/json-lsp`, equivalent to:

```sh
npm install --prefix ~/.local/share/nvim/json-lsp vscode-langservers-extracted@4.8.0
```

The config falls back to `vscode-json-language-server` on PATH when that
installation is absent; bump the pinned version in `lua/config/lsp_servers.lua`
to update.

Attaches to `json` and `jsonc` buffers, starting at the nearest ancestor holding
`package.json`, then `.git`. Diagnostics come in two kinds:

- **Syntax errors** — trailing commas, missing commas, unclosed braces,
  duplicate keys — always, for every JSON file.
- **Type/shape errors** — wrong value type, unknown property, missing required
  property — only where the document has a schema. A file's own `$schema` key is
  honoured, and `lsp/jsonls.lua` maps the common unschemaed filenames
  (`package.json`, `tsconfig*.json`, `jsconfig*.json`, `.eslintrc.json`,
  `.prettierrc`, `.markdownlint.json`, `.luarc.json`) to
  [SchemaStore](https://www.schemastore.org/) URLs. The server bundles no
  schemas of its own — VS Code supplies them there — so a filename matched by
  neither gets syntax checking only. Add entries to the `schemas` list to cover
  more.

Schemas are fetched over HTTP by the server, lazily, the first time a matching
file opens — nothing is downloaded at startup, and an offline session simply
falls back to syntax-only diagnostics for those files.

The navigation, diagnostic, and completion keys in the Python table apply here
too: completion suggests schema-known keys and enum values, and `K` shows a
property's schema description. `:lua vim.lsp.buf.format()` reformats on request;
there is no format-on-save. Diagnostics have no sign-column glyphs, matching the
other servers.

Treesitter highlights `json` buffers with the `json` parser. Files Neovim detects
as `jsonc` (notably `tsconfig.json`) have no parser available — nvim-treesitter's
main branch ships none — so they open unhighlighted; the language server still
attaches and checks them.

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
