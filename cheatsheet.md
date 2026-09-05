# Cheatsheet
---

## Vim External Filters (`!`)

**Usage:** Highlight text in Visual Mode, type `!`, then the command.
*Vim will automatically prepend `:'<,'>` (the range).*

| Command | Action |
| --- | --- |
| `!sort` | Sort lines alphabetically |
| `!sort -u` | Sort and remove duplicates (Unique) |
| `!nl` | Number every line |
| `!column -t` | Align text into a clean table |
| `!jq .` | Prettify/Format JSON |
| `!tr '[:lower:]' '[:upper:]'` | Convert text to UPPERCASE |
| `!tac` | Reverse line order (bottom to top) |
| `!rev` | Reverse characters on each line |

---

## Insert Command Output (`:r !`)

**Usage:** Inserts the output of a command *below* your cursor without overwriting text.

| Command | Action |
| --- | --- |
| `:r !date` | Insert current timestamp |
| `:r !ls` | Insert list of files in current directory |
| `:r !curl -s [URL]` | Fetch and insert content from a URL |

---

## Selecting a Function (no plugin)

Vim's built-in tricks to grab a whole function without treesitter text objects.
Keywords: function, select function, whole function, brace, %, matchit, text object.

| Sequence | Selects |
| --- | --- |
| `V%` | From current line to matching `{` / `}` / `(` / `)` / `[` / `]` (works well in C-family, JS; Lua `function`/`end` needs the built-in `matchit` plugin) |
| `Vj...j` | Visual-line then extend downward manually — language-agnostic fallback |
| `V]]` / `V][` | Extend to next section start / end (varies by filetype) |

Combine with `<leader>ay` after selecting.

For semantic `af`/`if`/`ac`/`ic` text objects you'd need `nvim-treesitter-textobjects`, but on nvim 0.12 that requires `brew install tree-sitter` (v2 branch). Deferred.

---

## Capture Command Output (`:redir`)

**Usage:** Capture the *messages* / output of one or more `:` commands into a register or file.
Keywords: redir, redirect, capture, copy command output, messages, save output.

| Command | Action |
| --- | --- |
| `:redir @+` \| run command \| `:redir END` | Capture output to system clipboard (paste with `Cmd+V`) |
| `:redir @a` \| run command \| `:redir END` | Capture output to register `a` (paste with `"ap`) |
| `:redir > /tmp/out.txt` \| run command \| `:redir END` | Capture to a file |
| `:redir >> file` | Append instead of overwrite |

**Note:** commands like `:Inspect` don't accept `|`-chaining (no `-bar` attribute), so run the three lines separately:
```
:redir @+
:Inspect
:redir END
```
For `:Inspect` specifically, `:InspectTree` opens the whole tree as a real buffer — use `<C-w>w` to jump in, then `<leader>aY` to yank it.

---

## Code Review (diffview.nvim)

**Workflow:** in your shell, `git fetch origin && git checkout <pr-branch>`, then open nvim.
Keywords: code review, pull request, PR, diff, review, diffview.

**Pane convention:** in the two-pane view, **left = base** (default branch), **right = head** (your PR branch). The status line's `[-]` on diffview buffers is expected — those are virtual buffers, not files on disk.

| Key / Command | Action |
| --- | --- |
| `<leader>dm` | Open diffview: current branch vs default branch (the "PR diff") |
| `<leader>dv` | Open diffview: working tree (uncommitted changes) |
| `<leader>dh` | File history of current file |
| `<leader>dH` | Branch history browser |
| `<leader>dc` | Close diffview tab |
| `<leader>df` | Toggle file panel (hide while reading diff, show to navigate) |
| `]c` / `[c` | Next / previous change (hunk) within a file |
| `]f` / `[f` | Next / previous changed file (inside diffview) |
| `]f` / `[f` | Next / previous changed file (inside diffview) |
| `:DiffviewOpen main...HEAD` | Manual open against a specific base branch |
| `<tab>` / `<s-tab>` | Alt: next / previous file |
| `gf` | Open the real file in a new tab (edit / take notes) |
| `:DiffviewToggleFiles` | Hide / show the file panel |

One-time repo fix if `<leader>dm` can't find the default branch:
```sh
git remote set-head origin --auto
```

---

## Window Management (resize, zoom, fullscreen)

Keywords: resize, zoom, fullscreen, maximize, split, window, pane.

**Move focus between windows:** `<C-w>h/j/k/l`.

| Key / Command | Action |
| --- | --- |
| `<C-w>>` / `<C-w><` | Widen / narrow current window by 1 column |
| `<C-w>+` / `<C-w>-` | Taller / shorter by 1 row |
| `<C-w>=` | Equalize all windows |
| `<C-w>\|` | Maximize current window width |
| `<C-w>_` | Maximize current window height |
| `10<C-w>>` | Widen by 10 columns (prefix with count for bigger steps) |
| `:vertical resize 60` | Set exact width |
| `:vertical resize +10` | Widen by 10 in one shot |
| `:tab split` (`:tab sp`) | Zoom / fullscreen current window in a new tab |
| `:tabclose` (`:tabc`) | Unzoom — close the zoom tab, restore original layout |
| `gt` / `gT` | Next / previous tab |
| `g<Tab>` | Flip to previously-visited tab (great with `<leader>?`) |
| `<leader>?` | Open (or jump to) this cheatsheet in a tab |
| `:tabonly` (`:tabo`) | Close all tabs except current |
| `:only` (`:on`) / `<C-w>o` | Close all windows in current tab except current |
| `:tabonly \| only` | Collapse to a single clean window |
| `:qa` / `:qa!` / `:wqa` | Quit all / force / write-all-then-quit |

---

## AI CLI Bridge (clipboard)

### Explain without leaving the diff

Select an unfamiliar expression in Visual mode and press `<leader>ae` (Space,
then a, then e). In Normal mode it explains the current line; a count includes
more lines. The explanation appears beside your diff without moving focus.
Narrow terminals put the support panes below the diff.

| Key / Command | Action |
| --- | --- |
| `<leader>ae` | Explain the current line or exact visual selection |
| `<leader>af` | Focus the explanation to read/scroll/select it |
| `<leader>aq` | Ask a follow-up about the last explained selection |
| `<leader>ap` | Pin selected text or the current line into private context notes |
| `<leader>an` | Edit the pinned context pane; `:w` saves |
| `<leader>ar` / Enter in a support pane | Return to the captured code position |
| `<leader>ax` / `q` in a support pane | Close support panes and cancel a pending explanation |
| `:ReviewContext` | Reopen the last explanation and notes |

The backend defaults to Copilot CLI using its configured model. Authenticate
with `copilot login` if necessary. To use Claude Code instead, set
`vim.g.review_context_provider = 'claude'` in `init.lua` (authenticate with
`claude auth login`). The bridge invokes the executable directly, not your
shell aliases. It disables assistant tools; the explanation uses the supplied
selection, up to 25 surrounding lines on either side, and your pinned notes.
Requests go to the selected assistant provider only when you ask.

Diffview selections use the actual pane contents and its commit/index label.
An old-side selection never silently becomes the working-tree version.
Values in explanations are inferred or example values, not executed traces.
Pinned facts are snapshots with a source location; they do not update as code
changes. Follow-ups stay attached to the last explained selection; use `ae`
again when you reach a different blocker.

Notes and the last successful answer live under
`stdpath('state')/review-context/<repository-id>/`, outside the checkout. Pins
save immediately; edited notes save with `:w`, on leaving the buffer, or on
exit. `:ReviewContext` restores the last answer after restarting; the original
Diffview must be reopened manually to restore a revision that is no longer
displayed. This support pane works with ordinary file buffers and Diffview;
the separate CodeReview plugin's custom buffers are not yet adapted.

These private notes do not post PR comments. In an existing `:CodeReview`
session, `<leader>cc` still opens its comment editor and `<leader>cs` submits.

### Existing clipboard workflow

Send code from nvim to an AI CLI (Copilot CLI, Claude Code, ...) running in another terminal tab.
Keywords: ai, copilot, claude, chat, ask, reference, selection, share.

**Workflow:**
1. `Cmd+T` in Terminal.app for a new tab; run `copilot` or `claude` there.
2. In nvim, select code (or none for whole buffer) and yank with the keymaps below.
3. `Cmd+\`` back to the AI tab, `Cmd+V`, hit enter.

| Key | Action |
| --- | --- |
| `<leader>ay` (visual mode) | Yank selection + `@path:lines` header to system clipboard |
| `<leader>ay` (normal mode) | Yank current line + `@path:line` header (prefix count: `5<leader>ay` = 5 lines) |
| `<leader>aY` (normal mode) | Yank whole buffer + `@path:lines` header |

The formatted paste looks like:
```
@src/foo.lua:10-25
```lua
... code ...
```
```
The `@path` reference lets both `copilot` and `claude` read the file themselves for extra context.
Each line in the body is prefixed with its buffer line number, so the assistant can refer to lines unambiguously.
Inside diffview the header resolves to the real file path, with a `(staged)` or `(at <sha>)` suffix when the pane is not the working file.

---

## Folds (show / hide collapsed lines)

Keywords: fold, unfold, collapse, expand, diff folds, show full file.

| Key | Action |
| --- | --- |
| `zR` | Open **all** folds (show full file, incl. unchanged diff context) |
| `zM` | Close all folds |
| `zo` / `zc` | Open / close fold under cursor |
| `za` | Toggle fold under cursor |
| `zj` / `zk` | Jump to next / previous fold |

---
