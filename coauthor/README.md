# coauthor

Comment threads on a document, shared by an editor and a coding agent. Comments
never go into the document: each document has a threads file in the state
directory, and this CLI is the only thing that writes it. Neovim calls it with
`--json`; an agent calls it from its shell. Design and rationale:
[docs/coauthor.md](../docs/coauthor.md).

## Install

From the repository root, `make deps` (or `nvim -l scripts/install_deps.lua
coauthor`) runs:

```sh
cargo install --path coauthor --locked
```

This puts `coauthor` in Cargo's bin directory (`~/.cargo/bin`), which must be on
`PATH` for agents to run it. The toolchain is pinned by `mise.toml`.

## Where threads live

| Platform | Directory |
| --- | --- |
| Linux, macOS | `$XDG_STATE_HOME/coauthor/` (default `~/.local/state/coauthor/`) |
| Windows | `%LOCALAPPDATA%\coauthor\` |

One file per document, named `<basename>-<hash>.threads.md`, where the hash is
the first 8 hex digits of the SHA-256 of the document's canonical absolute path.
The file's header records that path. Nothing is written to any repository.

Because the key is the absolute path, each worktree has its own threads, and
moving a document detaches them until you re-key:

```sh
coauthor path docs/rollout.md          # the threads file, for inspection
coauthor mv docs/old.md docs/new.md    # after moving or renaming a document
coauthor rm docs/rollout.md            # delete one document's threads
coauthor prune [--dry-run]             # delete threads of documents that no longer exist
```

Every command accepts `--json`. `coauthor --help` and `coauthor <command> --help`
list the rest.

## Threads file format

Readable Markdown with a strict shape. Do not edit it by hand: a section that
no longer parses is kept verbatim but ignored.

```markdown
<!-- coauthor v1 · written by the coauthor CLI; do not edit by hand
doc: /home/me/src/project/docs/rollout.md
round: open -->

## t1 · lines 12-14
> The rollout takes two weeks.

**me:** too vague, give phases

**ai:** {edited 12-18} Split into 3 phases.
```

- `round:` is `none` (never submitted), `open` or `done`.
- A thread header is `## tN · lines A-B`, optionally followed by `· drifted`
  and `· resolved`.
- `>` lines hold the anchor text; `was:` lines the anchor text from before the
  first re-anchor, kept until the thread is resolved.
- Messages are `**me:**` or `**ai:**`, append-only. A continuation line that
  would read as structure (`## `, `**me:**`, `**ai:**`, or a leading `\`) is
  stored with a `\` prefix.

## Concurrency

Every write takes an exclusive advisory lock on `.lock` in the state directory,
re-reads the threads file, changes it, writes a temporary file and renames it
over the original. Readers take no lock and never see a half-written file.

## Development

```sh
cargo test --manifest-path coauthor/Cargo.toml --locked
nvim -l scripts/run_tests.lua coauthor   # the same, as CI runs it
```
