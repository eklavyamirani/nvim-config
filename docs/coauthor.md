# Coauthor threads — design record

Status: **design, not implemented.** Captures decisions so far; sections marked
*Pinned* still need discussion before implementation.

## Goal

Leave comments on a document without touching it, submit them to Copilot or
Claude in one go, and have the agent edit the document and/or reply. Each
comment is a conversation thread that can go back and forth.

Builds on the AI clipboard bridge (`<leader>ay`), which already produces the
anchor (`@path:start-end` + text).

## Decided

### Comments live in a sidecar, never in the document

- `<file>.threads.md` next to the document. Inline comments are accident-prone
  and need cleanup.
- Ignored through the global `core.excludesFile` (`*.threads.md`), so no
  per-repo `.gitignore` edits.
- `:CoauthorClean` deletes the sidecar when done.

### The agent writes files

The agent (in the user's CLI tab, or headless) edits the document directly and
appends replies to the sidecar. Neovim does not mediate edits.

Consequence: the buffer reloads after agent edits, so extmarks do not survive
and the sidecar is the source of truth for anchors.

### Sidecar format

Markdown with a strict, dumb shape so both humans and agents can read it and
Neovim can parse it leniently. The header comment carries the agent rules, so the
file is self-describing for any agent or fresh session.

```markdown
<!-- ai-threads v1 · doc: docs/rollout.md
Agent rules:
- Reply to every thread whose last message is **me:**. Editing the doc is
  optional: answer without editing when the comment is a question or you disagree.
- Prefix each reply with {edited L-L} or {no edit}.
- If your edit moves a thread's anchored text, update its `lines` and `>` snapshot.
- If your edit removes a thread's anchored text, point `lines` at the
  replacement, or reply explaining why it is resolved.
- Never edit **me:** lines or threads marked `resolved`. -->

## t1 · lines 12-14
> The rollout takes two weeks.

**me:** too vague, give phases
**ai:** {edited 12-18} Split into 3 phases.
**me:** why 3 and not 2?
**ai:** {no edit} Phase 2 has the migration freeze; merging it with 1 hides that dependency.
```

- Threads are conversations. Any number of turns; a doc edit is an optional
  side effect of an AI turn, not the point of it.
- Unparseable thread headers are flagged and left untouched, never dropped.

### Status is derived, not stored

| Last message | Status |
|---|---|
| `**me:**` | awaiting ai |
| `**ai:**` | awaiting me |
| — | `resolved` (only stored status; set by the user) |

The agent never writes a status field, which removes a write-race source and a
format-error source.

### Submit

1. `:w` the document (required: otherwise the agent edits a stale file and the
   reload hits W12).
2. Write current anchor positions into the sidecar.
3. Snapshot the document to `stdpath('state')` as the review baseline.
4. Yank a short prompt; the rules live in the sidecar header:
   ```
   Address the open threads in @docs/rollout.md.threads.md (rules in its header).
   ```

Only threads awaiting ai are in scope.

**Experimental:** headless submit runs `claude -p` with Edit allowed on the
document and sidecar, using the same file contract.

### Review

`<leader>td` opens a native `diffthis` against the submit snapshot. Gitsigns
diffs against the index, which is the wrong baseline for uncommitted documents.
The reload is undoable as one step (`'undoreload'`).

### Anchoring and re-anchoring

Each thread stores `lines` plus a text snapshot (`>`). On every reload of the
document or sidecar, each thread walks a resolution ladder:

| # | Check | Result |
|---|---|---|
| 1 | text at stored `lines` matches snapshot | `anchored` |
| 2 | exact snapshot found elsewhere | `anchored`, `lines` updated. Multiple matches: nearest, marked `drifted` |
| 3 | fuzzy match within ±N lines (`vim.text.diff` score) | `drifted` above threshold — **experimental, off by default** |
| 4 | nothing | `orphaned`, keeping last-known line and snapshot |

- While the document is open, extmarks track anchors; their positions are
  flushed to the sidecar on `:w` and before submit.
- `drifted` is more dangerous than `orphaned`: it can sit on the wrong paragraph
  silently. It stays unconfirmed until accepted.
- Fuzzy matching ships off. A false orphan costs one re-anchor; a false drift
  misattaches a comment silently.
- Any thread can be re-anchored, not just orphans:
  - From the document: visual select → `<leader>tr` → fzf-lua picker (orphaned,
    then drifted, then the rest).
  - From the side split: `r` on a thread → jump to document → select → `<CR>`.
- Re-anchoring replaces the snapshot; the old one is kept as a `was:` line until
  the thread is resolved.

### Orphan discoverability

Many orphans are not failures: the agent removed the text because it addressed
the comment. Triage is re-anchor, resolve, or ignore.

| Surface | Behaviour | Default |
|---|---|---|
| `mini.notify` | on transitions only: "2 orphaned, 1 drifted · `<leader>tl`" | on |
| Side split | pinned **Needs anchor** section at the top with `was:` snapshots | on |
| Lualine | `awaiting me 2 · awaiting ai 1 · orphan 1`, foreground only, coauthor buffers only | on |
| Quickfix | `[orphan] t3: <snapshot>` at last-known line | on |
| In-buffer eol | dim `· orphan t3` at last-known line | **off** |

Notify also fires when threads flip to awaiting me: "3 replies · 1 edit".

### Thread views

Both, to compare in use:

- **Side split** — the sidecar filtered to the cursor's thread, plus the
  **Needs anchor** section. Keys: `<CR>` jump, `r` re-anchor, `a` accept drift,
  `x` resolve.
- **Float** — the thread under the cursor. *Experimental.*

Anchored lines are marked in the document (option B from the mockup):

- The line number is coloured by whose turn it is (peach: awaiting me, blue:
  awaiting ai). Foreground only, no signs, so gitsigns keeps the sign column.
- A dim thread id (`t1`) as end-of-line virtual text on the first anchored line,
  so quickfix and sidecar entries can be matched at a glance.

### Scope and toggle

- Any filetype.
- `:Coauthor` toggles the workflow for the current buffer.
- Auto-enabled for `markdown`, and for any file with an existing
  `<file>.threads.md`, so toggling once persists without extra state.

### Keymaps (proposed)

`<leader>ar` and `<leader>ax` are taken by the review-context panes, so
coauthor uses the free `<leader>t` (threads) prefix.

| Key | Action |
|---|---|
| `<leader>tc` | comment on line/selection (new thread, or reply inside one) |
| `<leader>tt` | open thread under cursor (side split) |
| `<leader>tf` | open thread under cursor (float) *(experimental)* |
| `]t` / `[t` | next / previous thread |
| `<leader>tl` | threads → quickfix |
| `<leader>ts` | `:w`, snapshot, yank submit prompt |
| `<leader>tS` | headless submit *(experimental)* |
| `<leader>td` | diff against submit snapshot |
| `<leader>tr` | re-anchor (visual) |
| `<leader>tx` | resolve thread |

### Experimental features

Experimental keymaps get an `(experimental)` suffix in `desc` so which-key shows
it, and a cheatsheet section lists them. Initially: headless submit, float view,
fuzzy drift matching.

## Findings from the mockup

A scripted mockup (real Neovim 0.12 with catppuccin, mini.notify, lualine and
render-markdown configured like this repo) surfaced these. Open until decided.

1. **Commented lines are hard to see.** With no signs or virtual text, nothing
   in the document marks an anchored line; only the side split reveals it when
   the cursor lands there. *Decided:* coloured line numbers plus an
   end-of-line thread id (see Thread views).
2. **render-markdown conceals the `[edited 18]` tag brackets** (treated as a
   shortcut link), in both the side split and the raw sidecar. That breaks the
   "keep source characters visible" rule. *Decided:* tags use braces,
   `{edited 18}` / `{no edit}`, which markdown leaves alone.
3. **The file watcher sees Neovim's own sidecar writes.** The mock ignores an
   event when the file content equals what Neovim last wrote.
4. **Watching the document file breaks on rename-based saves.** A save that
   writes a temp file and renames it (Neovim's `backupcopy=no`, and possibly
   agent edit tools) invalidates a per-file watch handle. The mock needed
   `backupcopy=yes` and watched only the sidecar.
5. **An orphan's last-known line can be another thread's line.** t3 orphaned at
   line 17, where t2 is anchored, so both quickfix entries point at line 17.
6. **mini.notify's top-right popup covers the top of the side split**, which is
   where the "Needs anchor" section lives. *Decided:* keep notify every round;
   the overlap lasts a few seconds.

The mock's re-anchor picker was the built-in `vim.ui.select`; the design keeps
fzf-lua.

## Pinned

### Change detection

Candidate: `vim.uv.new_fs_event` on the document and sidecar, then `:checktime`
and re-parse. Independent of terminal focus reporting (`FocusGained`, tmux
`focus-events`). Open: debouncing partial writes, editors that replace files via
rename (watch handle invalidation), behaviour when the document buffer is
modified.

### Write races

Neovim and the agent both write the sidecar. A comment added while the agent is
mid-edit can be clobbered. Candidate: a pending state after submit in which new
comments queue in memory and flush when the sidecar changes on disk or on
`:CoauthorDone`. Needs: the end-of-turn signal for the interactive CLI case,
and merge rules if both sides changed.
