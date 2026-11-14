-- Coauthor threads: comment on a document without touching it, submit the
-- comments to an agent, and converse per thread. The `coauthor` CLI owns the
-- threads; this module only calls it (always with --json) and never parses a
-- threads file. Design: docs/coauthor.md.
local M = {}
local api = vim.api
local ns = api.nvim_create_namespace('coauthor')
local group = api.nvim_create_augroup('coauthor', { clear = true })

-- buf -> { path, threads = { thread... }, by_id, marks = { id -> extmark }, revision, threads_path }
local docs = {}
M.docs = docs
local missing_notified = false
-- One CLI call at a time: every write prints a full snapshot, so snapshots
-- must arrive in the order the writes happened.
local queue, running = {}, false
local listeners = {}

local function cli() return vim.g.coauthor_command or 'coauthor' end

local function notify(message, level) vim.notify('Coauthor: ' .. message, level or vim.log.levels.INFO) end

-- `quiet` skips the one-time notice, for background checks on arbitrary files.
local function available(quiet)
  if vim.fn.executable(cli()) == 1 then return true end
  if not quiet and not missing_notified then
    missing_notified = true
    notify(('`%s` was not found, so threads are disabled. Install it with `make deps`.'):format(cli()),
      vim.log.levels.WARN)
  end
  return false
end

local function pump()
  if running or #queue == 0 then return end
  running = true
  local job = table.remove(queue, 1)
  local function finish(out)
    vim.schedule(function()
      running = false
      if out.code ~= 0 then
        local message = vim.trim(out.stderr or '')
        if job.on_error then job.on_error(message) else notify(message, vim.log.levels.ERROR) end
      else
        local ok, decoded = pcall(vim.json.decode, out.stdout or '', { luanil = { object = true, array = true } })
        if not ok then
          notify('unreadable output from ' .. cli() .. ': ' .. tostring(decoded), vim.log.levels.ERROR)
        elseif job.callback then
          job.callback(decoded)
        end
      end
      pump()
    end)
  end
  local ok, err = pcall(vim.system, vim.list_extend({ cli(), '--json' }, job.args),
    { text = true, stdin = job.stdin }, finish)
  if not ok then finish({ code = 1, stderr = tostring(err) }) end
end

-- Runs `coauthor --json ARGS...` asynchronously; `callback(snapshot)` on success.
function M.run(args, callback, opts)
  opts = opts or {}
  if not available(opts.quiet) then return false end
  table.insert(queue, { args = args, callback = callback, stdin = opts.stdin, on_error = opts.on_error })
  pump()
  return true
end

-- True when no CLI call is queued or running (for tests and callers that wait).
function M.idle() return not running and #queue == 0 end

-- Views (side split, statusline, ...) register here to redraw on new snapshots.
function M.on_change(fn) table.insert(listeners, fn) end

local function changed(buf)
  for _, fn in ipairs(listeners) do pcall(fn, buf) end
  vim.cmd('redrawstatus')
end

local function highlights()
  local ok, palettes = pcall(require, 'catppuccin.palettes')
  local palette = ok and palettes.get_palette() or {}
  -- Foreground only: the line number carries whose turn it is.
  api.nvim_set_hl(0, 'CoauthorAwaitingMe', { fg = palette.peach or '#fab387', default = true })
  api.nvim_set_hl(0, 'CoauthorAwaitingAi', { fg = palette.blue or '#89b4fa', default = true })
  api.nvim_set_hl(0, 'CoauthorId', { fg = palette.overlay0 or '#6c7086', default = true })
end

local status_hl = { awaiting_me = 'CoauthorAwaitingMe', awaiting_ai = 'CoauthorAwaitingAi' }

local function eligible(buf)
  local name = api.nvim_buf_get_name(buf)
  return api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == '' and name ~= '' and not name:find('^%a+://')
end

-- Range (1-based, inclusive) an anchor's extmark covers now, or nil once its text is gone.
local function mark_range(buf, mark)
  local found = api.nvim_buf_get_extmark_by_id(buf, ns, mark, { details = true })
  if not found[1] or found[3].invalid then return nil end
  local first, last = found[1] + 1, (found[3].end_row or found[1]) + 1
  if last < first then return nil end
  return first, last
end
M.mark_range = mark_range

local function place(buf, doc, thread, first, last)
  local count = api.nvim_buf_line_count(buf)
  if first > count then return end
  last = math.min(last, count)
  local end_line = api.nvim_buf_get_lines(buf, last - 1, last, false)[1] or ''
  doc.marks[thread.id] = api.nvim_buf_set_extmark(buf, ns, first - 1, 0, {
    id = doc.marks[thread.id],
    end_row = last - 1,
    end_col = #end_line,
    number_hl_group = status_hl[thread.status],
    virt_text = { { thread.id, 'CoauthorId' } },
    virt_text_pos = 'eol',
    invalidate = true,
    undo_restore = true,
  })
end

local function unmark(buf, doc, id)
  if doc.marks[id] then pcall(api.nvim_buf_del_extmark, buf, ns, doc.marks[id]) end
  doc.marks[id] = nil
end

-- Takes a snapshot printed by the CLI. While a buffer is open its extmarks are
-- the truth for positions, so existing marks keep theirs; `rebuild` (after a
-- load or reload) places every mark from the snapshot's resolved lines, and
-- `place` gives positions for threads just created from the buffer.
local function apply(buf, snapshot, opts)
  local doc = docs[buf]
  if not doc or not snapshot then return end
  opts = opts or {}
  doc.snapshot, doc.revision, doc.threads_path = snapshot, snapshot.revision, snapshot.path
  doc.threads, doc.by_id = snapshot.threads or {}, {}
  if opts.rebuild then
    api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    doc.marks = {}
  end
  local seen = {}
  for _, thread in ipairs(doc.threads) do
    doc.by_id[thread.id], seen[thread.id] = thread, true
    local range = opts.place and opts.place[thread.id]
    if thread.status == 'resolved' then
      unmark(buf, doc, thread.id)
    elseif range then
      place(buf, doc, thread, range[1], range[2])
    elseif doc.marks[thread.id] then
      local first, last = mark_range(buf, doc.marks[thread.id])
      if first then place(buf, doc, thread, first, last) end
    elseif thread.state ~= 'orphaned' and not doc.locked then
      place(buf, doc, thread, thread.lines[1], thread.lines[2])
    end
  end
  for id in pairs(doc.marks) do
    if not seen[id] then unmark(buf, doc, id) end
  end
  changed(buf)
end
M.apply = apply

function M.refresh(buf, opts)
  buf = buf or api.nvim_get_current_buf()
  local doc = docs[buf]
  if not doc then return end
  M.run({ 'list', doc.path }, function(snapshot) apply(buf, snapshot, opts) end)
end

function M.enable(buf, opts)
  buf = (buf == nil or buf == 0) and api.nvim_get_current_buf() or buf
  if docs[buf] then return true end
  if not eligible(buf) then
    if not (opts and opts.quiet) then notify('threads need a file buffer.', vim.log.levels.WARN) end
    return false
  end
  if not available() then return false end
  docs[buf] = { path = api.nvim_buf_get_name(buf), threads = {}, by_id = {}, marks = {} }
  M.refresh(buf, { rebuild = true })
  return true
end

function M.disable(buf)
  buf = (buf == nil or buf == 0) and api.nvim_get_current_buf() or buf
  if api.nvim_buf_is_valid(buf) then api.nvim_buf_clear_namespace(buf, ns, 0, -1) end
  docs[buf] = nil
  changed(buf)
end

function M.toggle()
  local buf = api.nvim_get_current_buf()
  if docs[buf] then
    M.disable(buf)
    notify('off for this buffer')
  elseif M.enable(buf) then
    notify('on for this buffer')
  end
end

function M.enabled(buf) return docs[(buf == nil or buf == 0) and api.nvim_get_current_buf() or buf] ~= nil end

-- The anchored thread covering `row` (1-based); the narrowest when anchors nest.
function M.thread_at(buf, row)
  local doc = docs[buf]
  if not doc then return nil end
  local best, span
  for id, mark in pairs(doc.marks) do
    local first, last = mark_range(buf, mark)
    if first and first <= row and row <= last and (not span or last - first < span) then
      best, span = doc.by_id[id], last - first
    end
  end
  return best
end

-- Current anchor positions as `coauthor sync` expects them.
local function anchors(buf)
  local doc, list = docs[buf], {}
  for id, mark in pairs(doc.marks) do
    local first, last = mark_range(buf, mark)
    if first then table.insert(list, { id = id, lines = { first, last } }) end
  end
  table.sort(list, function(a, b) return tonumber(a.id:sub(2)) < tonumber(b.id:sub(2)) end)
  return list
end

function M.sync(buf, callback)
  local doc = docs[buf]
  if not doc then return end
  local list = anchors(buf)
  if #list == 0 then
    if callback then callback() end
    return
  end
  M.run({ 'sync', doc.path, '--anchors', '-' }, function(snapshot)
    apply(buf, snapshot)
    if callback then callback(snapshot) end
  end, { stdin = vim.json.encode(list) })
end

local function selection()
  local a, b = vim.fn.getpos('v')[2], vim.fn.getpos('.')[2]
  api.nvim_feedkeys(api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
  return math.min(a, b), math.max(a, b)
end

-- `<leader>tc`: a new thread on the line or selection, or, in normal mode with
-- the cursor inside an anchor, a reply to that thread.
function M.comment(mode)
  local buf = api.nvim_get_current_buf()
  local first, last
  if mode == 'visual' then
    first, last = selection()
  else
    first = api.nvim_win_get_cursor(0)[1]
    last = first
  end
  if not M.enable(buf) then return end
  local doc = docs[buf]
  local thread = mode ~= 'visual' and M.thread_at(buf, first) or nil
  if thread then
    vim.ui.input({ prompt = ('Reply to %s: '):format(thread.id) }, function(text)
      if not text or vim.trim(text) == '' then return end
      M.run({ 'comment', doc.path, '--thread', thread.id, '--', text }, function(snapshot) apply(buf, snapshot) end)
    end)
    return
  end
  -- Anchor text comes from the buffer: mid-round, or with unsaved edits, the
  -- file on disk is not what the user selected. A provisional extmark follows
  -- the lines while the prompt and the CLI call are pending.
  local lines = api.nvim_buf_get_lines(buf, first - 1, last, false)
  local pending = api.nvim_buf_set_extmark(buf, ns, first - 1, 0,
    { end_row = last - 1, end_col = #lines[#lines], invalidate = true })
  local function drop() pcall(api.nvim_buf_del_extmark, buf, ns, pending) end
  vim.ui.input({ prompt = ('Comment on lines %d-%d: '):format(first, last) }, function(text)
    if not text or vim.trim(text) == '' then return drop() end
    M.run({ 'comment', doc.path, '--lines', first .. '-' .. last, '--anchor-text=' .. table.concat(lines, '\n'),
      '--', text }, function(snapshot)
      local a, b = mark_range(buf, pending)
      drop()
      local id = snapshot.result and snapshot.result.thread
      apply(buf, snapshot, { place = id and a and { [id] = { a, b } } or nil })
    end, { on_error = function(message)
      drop()
      notify(message, vim.log.levels.ERROR)
    end })
  end)
end

-- `]t` / `[t`: the next or previous anchor start, wrapping like 'wrapscan'.
-- Elsewhere they keep Neovim's default meaning, :tnext / :tprevious.
function M.jump(direction)
  local buf = api.nvim_get_current_buf()
  local doc = docs[buf]
  if not doc then
    local ok, err = pcall(vim.cmd, vim.v.count1 .. (direction > 0 and 'tnext' or 'tprevious'))
    if not ok then api.nvim_echo({ { tostring(err):match('E%d+:.*') or tostring(err), 'ErrorMsg' } }, true, {}) end
    return
  end
  local starts = {}
  for _, mark in pairs(doc.marks) do
    local first = mark_range(buf, mark)
    if first then table.insert(starts, first) end
  end
  if #starts == 0 then return notify('no anchored threads') end
  table.sort(starts)
  local row = api.nvim_win_get_cursor(0)[1]
  local target
  if direction > 0 then
    for _, first in ipairs(starts) do
      if first > row then target = first break end
    end
    target = target or (vim.o.wrapscan and starts[1])
  else
    for i = #starts, 1, -1 do
      if starts[i] < row then target = starts[i] break end
    end
    target = target or (vim.o.wrapscan and starts[#starts])
  end
  if target then api.nvim_win_set_cursor(0, { target, 0 }) end
end

-- ---------------------------------------------------------------- views

-- Unresolved threads without a live anchor in the buffer: the CLI found no
-- text for them, or the user deleted it.
function M.orphans(buf)
  local doc, list = docs[buf], {}
  if not doc then return list end
  for _, thread in ipairs(doc.threads) do
    if thread.status ~= 'resolved' and not (doc.marks[thread.id] and mark_range(buf, doc.marks[thread.id])) then
      table.insert(list, thread)
    end
  end
  return list
end

local function first_line(lines) return (lines and lines[1]) or '' end

local function last_message(thread)
  local message = thread.messages[#thread.messages]
  return message and (message.author .. ': ' .. vim.split(message.text, '\n', { plain = true })[1]) or ''
end

local status_label = { awaiting_me = 'awaiting me', awaiting_ai = 'awaiting ai', resolved = 'resolved' }

-- Markdown for one thread. `range` is where its anchor is in the buffer now.
local function thread_lines(thread, range)
  local place = range and ('lines %d-%d'):format(range[1], range[2]) or ('was line %d'):format(thread.lines[1])
  local header = ('## %s · %s · %s'):format(thread.id, place, status_label[thread.status])
  if range and thread.state == 'drifted' then header = header .. ' · drifted' end
  local lines = { header }
  for _, line in ipairs(thread.anchor) do table.insert(lines, line == '' and '>' or '> ' .. line) end
  for _, line in ipairs(thread.was or {}) do table.insert(lines, 'was: ' .. line) end
  for _, message in ipairs(thread.messages) do
    table.insert(lines, '')
    local text = vim.split(message.text, '\n', { plain = true })
    text[1] = ('**%s:** %s'):format(message.author, text[1])
    vim.list_extend(lines, text)
  end
  return lines
end

local function range_of(buf, thread)
  local doc = docs[buf]
  local mark = doc and doc.marks[thread.id]
  if not mark then return nil end
  local first, last = mark_range(buf, mark)
  return first and { first, last } or nil
end

-- The side split's text for the thread at the cursor (or `thread`), with the
-- pinned Needs anchor section on top. Returns lines and a line -> thread id map.
function M.render(buf, row, thread)
  local lines, ids = {}, {}
  local orphans = M.orphans(buf)
  if #orphans > 0 then
    vim.list_extend(lines, { '# Needs anchor', '' })
    for _, orphan in ipairs(orphans) do
      table.insert(lines, ('- %s · was line %d · %s'):format(orphan.id, orphan.lines[1], status_label[orphan.status]))
      ids[#lines] = orphan.id
      table.insert(lines, '  was: ' .. first_line(orphan.anchor))
      ids[#lines] = orphan.id
    end
    table.insert(lines, '')
  end
  thread = thread or (row and M.thread_at(buf, row))
  if thread then
    local start = #lines + 1
    vim.list_extend(lines, thread_lines(thread, range_of(buf, thread)))
    for i = start, #lines do ids[i] = thread.id end
  else
    table.insert(lines, 'No thread on this line. <leader>tc comments on it.')
  end
  return lines, ids
end

local split = {}

local function valid_win(win) return win and api.nvim_win_is_valid(win) end

local function split_thread()
  if not (split.buf and api.nvim_buf_is_valid(split.buf)) then return end
  local row = valid_win(split.win) and api.nvim_win_get_buf(split.win) == split.buf
    and api.nvim_win_get_cursor(split.win)[1]
  local id = row and split.ids[row]
  local doc = docs[split.doc]
  return doc and id and doc.by_id[id], split.doc
end

local function draw_split()
  if not valid_win(split.win) or not docs[split.doc] then return end
  local doc_win = vim.fn.bufwinid(split.doc)
  local row = doc_win ~= -1 and api.nvim_win_get_cursor(doc_win)[1] or nil
  local lines, ids = M.render(split.doc, row, split.pinned and docs[split.doc].by_id[split.pinned])
  split.ids = ids
  vim.bo[split.buf].modifiable = true
  api.nvim_buf_set_lines(split.buf, 0, -1, false, lines)
  vim.bo[split.buf].modifiable = false
end

function M.resolve(buf, thread)
  if not thread then return notify('no thread here') end
  M.run({ 'resolve', docs[buf].path, thread.id }, function(snapshot) apply(buf, snapshot) end)
end

-- Accepting a drift re-anchors to where the mark is now, which `coauthor move`
-- reads from the file: the buffer must be saved and outside a round.
function M.accept(buf, thread)
  local range = thread and range_of(buf, thread)
  if not range or thread.state ~= 'drifted' then return notify('no drifted thread here') end
  if docs[buf].locked then return notify('accept drifts after the round ends') end
  if vim.bo[buf].modified then return notify('save the document first, then accept') end
  M.run({ 'move', docs[buf].path, thread.id, range[1] .. '-' .. range[2] }, function(snapshot) apply(buf, snapshot) end)
end

local function jump_to(buf, thread)
  if not thread then return end
  local range = range_of(buf, thread)
  local line = range and range[1] or math.min(thread.lines[1], api.nvim_buf_line_count(buf))
  local win = vim.fn.bufwinid(buf)
  if win == -1 then
    vim.cmd('wincmd p')
    api.nvim_win_set_buf(0, buf)
    win = api.nvim_get_current_win()
  end
  api.nvim_set_current_win(win)
  api.nvim_win_set_cursor(win, { line, 0 })
end

local split_keys = {}

function M.open_split()
  local buf = api.nvim_get_current_buf()
  if buf == split.buf then return end
  if not M.enable(buf) then return end
  split.doc, split.pinned = buf, nil
  if not (split.buf and api.nvim_buf_is_valid(split.buf)) then
    split.buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_name(split.buf, 'coauthor://threads')
    vim.bo[split.buf].filetype = 'markdown'
    vim.bo[split.buf].modifiable = false
    for _, key in ipairs(split_keys) do
      vim.keymap.set('n', key[1], key[2], { buffer = split.buf, desc = key[3] })
    end
  end
  if not valid_win(split.win) then
    local doc_win = api.nvim_get_current_win()
    vim.cmd('botright vertical sbuffer ' .. split.buf)
    split.win = api.nvim_get_current_win()
    api.nvim_win_set_width(split.win, math.max(40, math.floor(vim.o.columns / 3)))
    for option, value in pairs({ number = false, relativenumber = false, signcolumn = 'no', wrap = true,
      linebreak = true, winfixwidth = true, cursorline = false }) do
      vim.wo[split.win][option] = value
    end
    api.nvim_set_current_win(doc_win)
  end
  draw_split()
end

function M.close_split()
  if valid_win(split.win) then api.nvim_win_close(split.win, true) end
  split.win = nil
end

split_keys = {
  { '<CR>', function()
    local thread, buf = split_thread()
    jump_to(buf, thread)
  end, 'Coauthor: jump to the thread in the document' },
  { 'x', function()
    local thread, buf = split_thread()
    if buf then M.resolve(buf, thread) end
  end, 'Coauthor: resolve thread' },
  { 'a', function()
    local thread, buf = split_thread()
    if buf then M.accept(buf, thread) end
  end, 'Coauthor: accept drifted anchor' },
  { 'q', M.close_split, 'Coauthor: close threads split' },
}

local float = {}

-- Experimental: the thread under the cursor in a float, closed on the next move.
function M.open_float()
  local buf = api.nvim_get_current_buf()
  if not M.enable(buf) then return end
  local thread = M.thread_at(buf, api.nvim_win_get_cursor(0)[1])
  if not thread then return notify('no thread on this line') end
  if valid_win(float.win) then api.nvim_win_close(float.win, true) end
  local lines = thread_lines(thread, range_of(buf, thread))
  local fbuf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(fbuf, 0, -1, false, lines)
  vim.bo[fbuf].filetype = 'markdown'
  vim.bo[fbuf].modifiable = false
  local width = math.min(80, vim.o.columns - 4)
  local height = 0
  for _, line in ipairs(lines) do height = height + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / width)) end
  float.win = api.nvim_open_win(fbuf, false, {
    relative = 'cursor', row = 1, col = 0, width = width, height = math.min(height, math.floor(vim.o.lines / 2)),
    style = 'minimal', border = vim.o.winborder ~= '' and vim.o.winborder or 'single',
  })
  vim.wo[float.win].wrap, vim.wo[float.win].linebreak = true, true
  float.doc = buf
  return float.win
end

-- Orphans first (at their last-known line), then every other unresolved thread.
function M.quickfix_items(buf)
  local doc, items = docs[buf], {}
  if not doc then return items end
  local orphaned = {}
  for _, orphan in ipairs(M.orphans(buf)) do
    orphaned[orphan.id] = true
    table.insert(items, { bufnr = buf, lnum = orphan.lines[1],
      text = ('[orphan] %s · was line %d: %s'):format(orphan.id, orphan.lines[1], first_line(orphan.anchor)) })
  end
  local rest = {}
  for _, thread in ipairs(doc.threads) do
    local range = range_of(buf, thread)
    if thread.status ~= 'resolved' and not orphaned[thread.id] and range then
      table.insert(rest, { bufnr = buf, lnum = range[1], end_lnum = range[2],
        text = ('%s · %s · %s'):format(thread.id, status_label[thread.status], last_message(thread)) })
    end
  end
  table.sort(rest, function(a, b) return a.lnum < b.lnum end)
  return vim.list_extend(items, rest)
end

function M.quickfix()
  local buf = api.nvim_get_current_buf()
  if not M.enable(buf) then return end
  local items = M.quickfix_items(buf)
  if #items == 0 then return notify('no open threads') end
  vim.fn.setqflist({}, ' ', { title = 'Coauthor threads', items = items })
  vim.cmd('copen')
end

-- Lualine: `awaiting me 2 · awaiting ai 1 · orphan 1`, zero counts left out.
function M.statusline()
  local buf = api.nvim_get_current_buf()
  local doc = docs[buf]
  if not doc then return '' end
  -- Exclusive buckets: an orphan counts only as an orphan.
  local orphaned = {}
  for _, orphan in ipairs(M.orphans(buf)) do orphaned[orphan.id] = true end
  local counts = { awaiting_me = 0, awaiting_ai = 0 }
  for _, thread in ipairs(doc.threads) do
    if counts[thread.status] and not orphaned[thread.id] then counts[thread.status] = counts[thread.status] + 1 end
  end
  local parts = {}
  if counts.awaiting_me > 0 then table.insert(parts, 'awaiting me ' .. counts.awaiting_me) end
  if counts.awaiting_ai > 0 then table.insert(parts, 'awaiting ai ' .. counts.awaiting_ai) end
  if next(orphaned) then table.insert(parts, 'orphan ' .. vim.tbl_count(orphaned)) end
  return table.concat(parts, ' · ')
end

M.lualine = {
  function() return M.statusline() end,
  cond = function() return M.enabled(0) end,
}

function M.setup()
  highlights()
  api.nvim_create_autocmd('ColorScheme', { group = group, callback = highlights })
  api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'markdown',
    callback = function(event)
      if eligible(event.buf) then M.enable(event.buf, { quiet = true }) end
    end,
  })
  -- Any other file is enabled when it already has threads; the check is a
  -- background `coauthor path`, silent when the CLI is missing.
  api.nvim_create_autocmd('BufReadPost', {
    group = group,
    callback = function(event)
      local buf = event.buf
      if docs[buf] then return M.refresh(buf, { rebuild = true }) end
      if not eligible(buf) then return end
      M.run({ 'path', api.nvim_buf_get_name(buf) }, function(info)
        if info.exists and api.nvim_buf_is_valid(buf) then M.enable(buf, { quiet = true }) end
      end, { quiet = true, on_error = function() end })
    end,
  })
  api.nvim_create_autocmd('BufWritePost', {
    group = group,
    callback = function(event)
      if docs[event.buf] then M.sync(event.buf) end
    end,
  })
  api.nvim_create_autocmd('BufWipeout', {
    group = group,
    callback = function(event) docs[event.buf] = nil end,
  })
  -- The side split follows the cursor's thread.
  api.nvim_create_autocmd({ 'CursorMoved', 'BufEnter' }, {
    group = group,
    callback = function(event)
      if event.buf ~= split.buf and docs[event.buf] and valid_win(split.win) then
        split.doc, split.pinned = event.buf, nil
        draw_split()
      end
    end,
  })
  M.on_change(function(buf) if buf == split.doc then draw_split() end end)
  api.nvim_create_autocmd({ 'CursorMoved', 'InsertEnter', 'BufLeave' }, {
    group = group,
    callback = function(event)
      if event.buf == float.doc and valid_win(float.win) then api.nvim_win_close(float.win, true) end
    end,
  })
  api.nvim_create_user_command('Coauthor', M.toggle, { desc = 'Toggle coauthor threads for this buffer' })
  vim.keymap.set('n', '<leader>tc', function() M.comment('line') end,
    { desc = 'Coauthor: comment on line, or reply in a thread' })
  vim.keymap.set('x', '<leader>tc', function() M.comment('visual') end, { desc = 'Coauthor: comment on selection' })
  vim.keymap.set('n', '<leader>tt', M.open_split, { desc = 'Coauthor: open thread in side split' })
  vim.keymap.set('n', '<leader>tf', M.open_float, { desc = 'Coauthor: open thread in float (experimental)' })
  vim.keymap.set('n', '<leader>tl', M.quickfix, { desc = 'Coauthor: threads to quickfix' })
  vim.keymap.set('n', '<leader>tx', function()
    local buf = api.nvim_get_current_buf()
    if not docs[buf] then return notify('off for this buffer (:Coauthor)') end
    M.resolve(buf, M.thread_at(buf, api.nvim_win_get_cursor(0)[1]))
  end, { desc = 'Coauthor: resolve thread' })
  vim.keymap.set('n', ']t', function() M.jump(1) end, { desc = 'Coauthor: next thread (else :tnext)' })
  vim.keymap.set('n', '[t', function() M.jump(-1) end, { desc = 'Coauthor: previous thread (else :tprevious)' })
end

return M
