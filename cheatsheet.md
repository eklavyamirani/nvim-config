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
