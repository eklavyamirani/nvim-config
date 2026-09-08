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
| `<leader>aa` | Ask a specific question about the current line or exact visual selection |
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

To ask something specific, select code and press `<leader>aa`, then type your
question and Enter. For example: “What does this expand to if the path contains
spaces?” No prior explanation is needed. The code is captured before the input
prompt opens; the question and answer appear in the existing support pane and
are saved together. Escape or an empty question sends nothing. The shortcut
also appears in the Diffview code pane's `g?` help.

Diffview selections use the actual pane contents and its commit/index label.
An old-side selection never silently becomes the working-tree version.
Values in explanations are inferred or example values, not executed traces.
Pinned facts are snapshots with a source location; they do not update as code
changes. Follow-ups (`aq`) stay attached to the last explained or questioned
selection; use `ae` or `aa` when you reach a different blocker.

Notes and the last successful answer live under
`stdpath('state')/review-context/<repository-id>/`, outside the checkout. Pins
save immediately; edited notes save with `:w`, on leaving the buffer, or on
exit. `:ReviewContext` restores the last answer after restarting; the original
Diffview must be reopened manually to restore a revision that is no longer
displayed. This support pane works with ordinary file buffers and Diffview;
the separate CodeReview plugin's custom buffers are not yet adapted.

These private notes do not post PR comments. In an existing `:CodeReview`
session, `<leader>cc` still opens its comment editor and `<leader>cs` submits.

### Organize files in the Diffview panel

Long file-panel rows wrap so filenames and paths remain readable. Added and
untracked files use a single code pane; modified files retain their normal
comparison layout. File navigation and native marks preserve reading positions
within the open review.

Use `:Notifications` or `<leader>nh` to open mini.notify's complete session
history in a separate tab. The buffer supports normal selection and yanking;
`q` closes it. These notifications have their own history, separate from
`:messages`.

Branch/PR and uncommitted comparisons use Diffview's existing file panel for
review ordering. Each file has a virtual review label beside its normal Git status:
`[todo]` = not yet reviewed, `[done]` = done, `[later]` = come back later.

| Key | Action |
| --- | --- |
| `<leader>ao` / `:ReviewRoute` | Focus the existing file panel |
| `g?` in the file panel | Native help, including these review shortcuts |
| `gs` in the file panel | Cycle default → AI → custom order |
| `gd` / `ga` / `gc` in the file panel | Select default / saved AI / saved custom order |
| `i` in default or AI order | Toggle tree/list view; each choice is saved |
| `J` / `K` in the file panel | Move the selected file down/up and save as custom |
| `md` in the file panel | Mark done |
| `ml` in the file panel | Mark come back later |
| `mn` in the file panel | Reset to not yet reviewed |
| Enter / `<Tab>` / `<S-Tab>` | Normal Diffview open/next/previous, following your order |
| `]r` / `[r` | Next/previous file in the same panel order |
| `go` in the file panel | Generate or replace the saved AI order |

There is no separate route window. Opening the panel does not call an assistant.
Manual ordering uses a flat list so files can move across directories; the normal
Git statuses, diff statistics, file paths, and selection behavior stay in the
native panel. Review labels do not stage files or submit GitHub reviews.

The panel's `Order:` line shows the active choice. Default supports Diffview's
native tree/list view (`i`), including folder folding and review labels. Its
tree/list choice is restored when switching back or reopening the comparison.
AI order defaults to a directory tree within each review group. Group order is
preserved; directories appear where their first suggested file occurs, bringing
their other files together. The same directory can appear in multiple groups.
Navigation follows the displayed tree, and normal folder folding works. Press
`i` for the original flat AI sequence; this choice is saved separately from the
default layout. Custom order uses a flat list. Orders are saved independently;
switching never overwrites either. `J`/`K` edits the displayed order and saves the result as custom, leaving
the saved AI order intact. Before any manual edits, custom uses the default order.

All orders, the active choice, and review marks save automatically and privately.
Committed reviews are scoped to the repository, exact compared commits, and
visible file set. They survive refreshes and Neovim restarts. Review marks are
shared across the three orders. Previously saved single orders become custom;
old read markers become `done`.

`ga` (or cycling into AI with `gs`) reuses the saved suggestion without a new
request. If none exists, it generates one. `go` explicitly requests a fresh
suggestion using the same assistant as explanations and bounded diff excerpts,
then selects the AI order. Review marks, custom order, and every changed file
are retained. AI suggestions partition the diff into named review tasks, each
with a shared review question and a contiguous list of files. Group headings
and questions appear as virtual lines above each group's tree or list in AI
mode and remain visible when folders are collapsed; native file navigation
skips them. Custom and default orders do not display AI groups. Use `go` to replace
an older saved suggestion with the new grouped format.

Large patches are sampled across the diff, including the beginning and end,
instead of sending only their first lines. The assistant still sees incomplete
code. Responses with missing/duplicate IDs or groups mixing Git sections are
rejected, retaining the previous orders. A manual move or switching to a saved
order cancels a pending suggestion. Suggested dependencies are inferred,
not proven. Set `vim.g.review_route_priority = 'risk'` before requesting a
suggestion to prioritize consequential changes instead of understanding.

Use `<leader>dv` / `:DiffviewOpen` for uncommitted changes, or
`:DiffviewOpen --cached` for staged changes only. The same review shortcuts work.
Working-tree state is saved per worktree, comparison, and path filter. Adding
or removing changed files preserves the remaining files' orders and marks.

Staged and unstaged entries have separate marks, including when they share a
path. `J`/`K` and AI ordering operate within each section. Native staging and
unstaging still work; an entry newly appearing in another section starts at
`todo`. On opening or refreshing (`R`), saved diffs are checked asynchronously;
an entry whose diff changed returns to `todo`, while unchanged entries keep
their marks. The tree/list choice and all orders survive restarting Neovim.

AI excerpts use each entry's actual comparison (HEAD/index/working tree),
including untracked files, renames, and deletions. A response is discarded if
those diffs change during the request. These checks use saved files and the Git
index; save buffer edits and refresh to update their review state. File-history
views retain their ordinary behavior.

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
