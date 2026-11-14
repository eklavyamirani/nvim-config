-- Shared setup for the coauthor Neovim tests: a private state directory, the
-- debug CLI built by `cargo test`, captured notifications and prompt answers.
local api = vim.api
local windows = vim.fn.has('win32') == 1
local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)
vim.g.mapleader = ' '
vim.cmd('filetype on')
vim.o.columns, vim.o.lines = 200, 60

local H = { root = root, temp = vim.fn.tempname(), notices = {}, prompts = {} }
vim.fn.mkdir(H.temp .. '/state', 'p')
vim.fn.mkdir(H.temp .. '/docs', 'p')
-- The CLI reads these from the environment Neovim passes on.
vim.env.XDG_STATE_HOME = H.temp .. '/state'
vim.env.LOCALAPPDATA = H.temp .. '/state'
H.binary = root .. '/coauthor/target/debug/coauthor' .. (windows and '.exe' or '')
assert(vim.fn.executable(H.binary) == 1, 'build the CLI first (cargo test): ' .. H.binary)
vim.g.coauthor_command = H.binary

H.original_notify = vim.notify
vim.notify = function(message, level) table.insert(H.notices, { message = message, level = level }) end

H.coauthor = require('config.coauthor')
H.coauthor.setup()
H.ns = api.nvim_create_namespace('coauthor')

function H.idle() assert(vim.wait(10000, H.coauthor.idle, 10), 'coauthor CLI calls did not finish') end

-- Answers the next vim.ui.input prompt with `text` (nil cancels).
function H.answer(text)
  vim.ui.input = function(opts, on_confirm)
    table.insert(H.prompts, opts.prompt)
    on_confirm(text)
  end
end

function H.cli(...)
  local result = vim.system({ H.binary, '--json', ... }, { text = true }):wait()
  assert(result.code == 0, result.stderr)
  return vim.json.decode(result.stdout)
end

function H.doc(name, lines)
  local path = H.temp .. '/docs/' .. name
  vim.fn.writefile(lines, path)
  return path
end

-- Anchor marks by thread id: { first, last, hl }.
function H.marks(buf)
  local found = {}
  for _, mark in ipairs(api.nvim_buf_get_extmarks(buf, H.ns, 0, -1, { details = true })) do
    local details = mark[4]
    if details.virt_text then
      found[details.virt_text[1][1]] = {
        first = mark[2] + 1, last = details.end_row + 1, hl = details.number_hl_group, id_hl = details.virt_text[1][2],
      }
    end
  end
  return found
end

function H.thread(state, id)
  for _, thread in ipairs(state.threads) do
    if thread.id == id then return thread end
  end
end

function H.buffer_text(buf) return table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), '\n') end

function H.finish(message)
  vim.notify = H.original_notify
  local errors = vim.tbl_filter(function(n) return n.level == vim.log.levels.ERROR end, H.notices)
  assert(#errors == 0, vim.inspect(errors))
  print(message)
  vim.cmd('qa!')
end

return H
