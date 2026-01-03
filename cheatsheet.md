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
