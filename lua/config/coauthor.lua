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
  M.watch(buf)
  if doc.round and snapshot.round == 'done' then M.end_round(buf, 'done') end
end
M.apply = apply

function M.refresh(buf, opts)
  buf = buf or api.nvim_get_current_buf()
  local doc = docs[buf]
  if not doc then return end
  M.run({ 'list', doc.path }, function(snapshot)
    apply(buf, snapshot, opts)
    if opts and opts.done then opts.done(snapshot) end
  end)
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
  if docs[buf] and docs[buf].round then return notify('end the round first (:CoauthorDone or :CoauthorCancel)') end
  if api.nvim_buf_is_valid(buf) then api.nvim_buf_clear_namespace(buf, ns, 0, -1) end
  M.unwatch(buf)
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
  { 'r', function()
    local thread, buf = split_thread()
    if buf then M.start_reanchor(buf, thread) end
  end, 'Coauthor: re-anchor thread' },
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

-- ---------------------------------------------------------------- re-anchoring

-- Threads to offer for a re-anchor: orphaned, then drifted, then the rest.
function M.reanchor_candidates(buf)
  local doc = docs[buf]
  if not doc then return {} end
  local groups = { {}, {}, {} }
  local orphaned = {}
  for _, orphan in ipairs(M.orphans(buf)) do orphaned[orphan.id] = true end
  for _, thread in ipairs(doc.threads) do
    if thread.status ~= 'resolved' then
      local range = range_of(buf, thread)
      local item = { thread = thread }
      if orphaned[thread.id] then
        item.group, item.text = 1, ('%s · orphaned · was line %d: %s'):format(thread.id, thread.lines[1],
          first_line(thread.anchor))
      else
        local drifted = thread.state == 'drifted'
        item.group = drifted and 2 or 3
        item.text = ('%s · %s · lines %d-%d: %s'):format(thread.id, drifted and 'drifted' or status_label[thread.status],
          range[1], range[2], first_line(thread.anchor))
      end
      table.insert(groups[item.group], item)
    end
  end
  local items = {}
  for _, list in ipairs(groups) do vim.list_extend(items, list) end
  return items
end

-- fzf-lua when it is loaded, vim.ui.select otherwise.
function M.pick(items, prompt, on_choice)
  local ok, fzf = pcall(require, 'fzf-lua')
  if ok and vim.fn.executable('fzf') == 1 then
    local by_text = {}
    for _, item in ipairs(items) do by_text[item.text] = item end
    fzf.fzf_exec(vim.tbl_map(function(item) return item.text end, items), {
      prompt = prompt .. '> ',
      actions = { ['default'] = function(selected) on_choice(selected and by_text[selected[1]]) end },
    })
  else
    vim.ui.select(items, { prompt = prompt, format_item = function(item) return item.text end }, on_choice)
  end
end

-- Re-anchors `thread` to lines `first`-`last` (saved immediately: `coauthor
-- move` takes the anchor text from the file, so unsaved edits are written first).
local function move(buf, thread, first, last)
  local doc = docs[buf]
  if doc.round then return notify('re-anchor after the round ends') end
  if vim.bo[buf].modified then
    local ok, err = pcall(api.nvim_buf_call, buf, function() vim.cmd('silent write') end)
    if not ok then return notify(tostring(err):match('E%d+:.*') or tostring(err), vim.log.levels.ERROR) end
  end
  M.run({ 'move', doc.path, thread.id, first .. '-' .. last }, function(snapshot)
    apply(buf, snapshot, { place = { [thread.id] = { first, last } } })
    notify(('%s anchored to lines %d-%d'):format(thread.id, first, last))
  end)
end

-- Visual `<leader>tr`: pick the thread to anchor to the selection.
function M.reanchor_selection()
  local buf = api.nvim_get_current_buf()
  local first, last = selection()
  local doc = docs[buf]
  if not doc then return notify('off for this buffer (:Coauthor)') end
  if doc.round then return notify('re-anchor after the round ends') end
  local items = M.reanchor_candidates(buf)
  if #items == 0 then return notify('no open threads') end
  M.pick(items, ('Anchor to lines %d-%d'):format(first, last), function(item)
    if item then move(buf, item.thread, first, last) end
  end)
end

-- The range to suggest: the last AI reply's `{edited L-L}` (agents often say
-- where the text went even when they forget `coauthor move`), else the
-- current or last-known lines.
function M.suggestion(buf, thread)
  for i = #thread.messages, 1, -1 do
    local message = thread.messages[i]
    if message.author == 'ai' then
      if message.edited and message.edited[1] then
        local range = message.edited[1]
        return math.min(range[1], api.nvim_buf_line_count(buf)), math.min(range[2], api.nvim_buf_line_count(buf))
      end
      break
    end
  end
  local range = range_of(buf, thread)
  if range then return range[1], range[2] end
  local line = math.min(thread.lines[1], api.nvim_buf_line_count(buf))
  return line, line
end

-- Side split `r`: select the suggestion in the document; `<CR>` confirms
-- (after adjusting the selection, if needed), leaving Visual mode cancels.
function M.start_reanchor(buf, thread)
  local doc = docs[buf]
  if not (doc and thread) then return notify('no thread here') end
  if doc.round then return notify('re-anchor after the round ends') end
  local first, last = M.suggestion(buf, thread)
  local win = vim.fn.bufwinid(buf)
  if win == -1 then
    vim.cmd('wincmd p')
    api.nvim_win_set_buf(0, buf)
    win = api.nvim_get_current_win()
  end
  api.nvim_set_current_win(win)
  doc.reanchoring = thread.id
  vim.keymap.set('x', '<CR>', function()
    -- Cleared before leaving Visual mode, which would otherwise read as a cancel.
    local pending = doc.reanchoring and doc.by_id[doc.reanchoring]
    doc.reanchoring = nil
    pcall(vim.keymap.del, 'x', '<CR>', { buffer = buf })
    local a, b = selection()
    if pending then move(buf, pending, a, b) end
  end, { buffer = buf, desc = 'Coauthor: anchor the thread here' })
  vim.cmd(('normal! %dGV%dG'):format(first, last))
  notify(('%s: adjust the selection, <CR> anchors it, <Esc> cancels'):format(thread.id))
end

-- Leaving Visual mode without <CR> cancels a pending re-anchor.
local function reanchor_mode_changed(event)
  local doc = docs[event.buf]
  if not (doc and doc.reanchoring) or vim.v.event.new_mode:match('^[vV\22]') then return end
  doc.reanchoring = nil
  pcall(vim.keymap.del, 'x', '<CR>', { buffer = event.buf })
  notify('re-anchor cancelled')
end

-- ---------------------------------------------------------------- headless submit (experimental)

M.options = {}

-- The agent command for a headless round: the bridge's provider
-- (`vim.g.review_context_provider`), allowed to edit only the document and to
-- run only `coauthor`. `M.options.agent_command(prompt, ctx)` replaces it.
function M.agent_command(prompt, ctx)
  if M.options.agent_command then return M.options.agent_command(prompt, ctx) end
  local provider = vim.g.review_context_provider or 'copilot'
  if provider == 'claude' then
    return { 'claude', '-p', prompt, '--output-format', 'text', '--permission-mode', 'dontAsk',
      '--tools', 'Read,Grep,Glob,Edit,Write,Bash', '--allowedTools', 'Bash(coauthor *)', 'Edit(./' .. ctx.relative .. ')',
      '--strict-mcp-config', '--mcp-config', '{"mcpServers":{}}', '--no-session-persistence' }
  end
  if provider ~= 'copilot' then error('Set review_context_provider to copilot or claude.') end
  local ok, bridge = pcall(require, 'config.review_context')
  return { 'copilot', '--silent', '--disable-builtin-mcps', '--no-ask-user', '--no-auto-update', '--no-color',
    '--stream', 'off', '--prompt', prompt,
    '--allow-tool=shell(coauthor:*),write(' .. ctx.relative .. '),read' }, ok and bridge.copilot_env(ctx.root) or nil
end

local function tail(text, lines)
  local all = vim.split(vim.trim(text or ''), '\n', { plain = true })
  return table.concat(vim.list_slice(all, math.max(1, #all - lines + 1)), '\n')
end

-- `<leader>tS`: submit, then run the agent without a terminal. Its exit ends
-- the round, running `coauthor done` if the agent did not.
function M.submit_headless()
  M.submit({ start = function(_, buf)
    local doc = docs[buf]
    local round = doc.round
    local root = vim.fs.root(doc.path, '.git') or vim.fs.dirname(doc.path)
    local relative = vim.fs.relpath(root, doc.path) or doc.path
    local ok, argv, env = pcall(M.agent_command, M.prompt_for(relative), { path = doc.path, root = root, relative = relative })
    local started, job
    if ok then
      started, job = pcall(vim.system, argv, { cwd = root, env = env, text = true }, function(out)
        vim.schedule(function()
          local failed = out.code ~= 0 and not round.cancelled
          if failed then
            notify(('agent exited with %s:\n%s'):format(out.signal ~= 0 and ('signal ' .. out.signal) or out.code,
              tail(out.stderr ~= '' and out.stderr or out.stdout, 8)), vim.log.levels.ERROR)
          end
          -- Still this round: the agent did not run `coauthor done`.
          if docs[buf] and docs[buf].round == round then
            M.run({ 'done', doc.path }, function(snapshot) apply(buf, snapshot) end)
          end
        end)
      end)
    end
    if not (ok and started) then
      notify('could not start the agent: ' .. tostring(ok and job or argv), vim.log.levels.ERROR)
      return M.end_round(buf, 'cancelled')
    end
    round.job = job
    notify(('round open · %s is working headless; :CoauthorCancel stops it'):format(argv[1]))
  end })
end

-- ---------------------------------------------------------------- change detection

-- Directory watches, shared by every document in a directory. A per-file watch
-- dies when a save replaces the file by rename, which Neovim ('backupcopy'
-- auto) and the CLI both do, so the directory is watched and events are
-- filtered by name.
local watches = {} -- dir -> { handle, names = { [name] = { [key] = callback } } }
local generations = {}

local function debounce(key, fn)
  generations[key] = (generations[key] or 0) + 1
  local generation = generations[key]
  vim.defer_fn(function()
    if generations[key] == generation then fn() end
  end, 100)
end

local function watch(path, key, callback)
  local dir = vim.fs.dirname(path)
  dir = vim.uv.fs_realpath(dir) or dir
  local name = vim.fs.basename(path)
  local entry = watches[dir]
  if not entry then
    local handle = vim.uv.new_fs_event()
    if not handle then return end
    entry = { handle = handle, names = {} }
    local ok = handle:start(dir, {}, function(err, filename)
      if err then return end
      vim.schedule(function()
        local base = filename and vim.fs.basename(filename)
        for watched, callbacks in pairs(entry.names) do
          -- Some platforms report no name; treat that as "anything changed".
          if not base or base == watched then
            for id, fn in pairs(callbacks) do debounce(id, fn) end
          end
        end
      end)
    end)
    if not ok then
      handle:close()
      return
    end
    watches[dir] = entry
  end
  entry.names[name] = entry.names[name] or {}
  entry.names[name][key] = callback
end

local function unwatch(key)
  for dir, entry in pairs(watches) do
    for name, callbacks in pairs(entry.names) do
      callbacks[key] = nil
      if not next(callbacks) then entry.names[name] = nil end
    end
    if not next(entry.names) then
      entry.handle:stop()
      entry.handle:close()
      watches[dir] = nil
    end
  end
end

local function read_file(path)
  local fd = vim.uv.fs_open(path, 'r', 438)
  if not fd then return nil end
  local stat = vim.uv.fs_fstat(fd)
  local data = stat and vim.uv.fs_read(fd, stat.size, 0)
  vim.uv.fs_close(fd)
  return data
end

-- A threads-file change refreshes the views, unless it is the state Neovim's
-- own last CLI call already returned.
local function threads_changed(buf)
  local doc = docs[buf]
  if not doc or not doc.threads_path then return end
  local data = read_file(doc.threads_path)
  if data and doc.revision and vim.fn.sha256(data) == doc.revision then return end
  M.refresh(buf)
end

-- A document change outside a round reloads an unmodified buffer (the reload
-- re-resolves anchors); with unsaved edits Neovim's W12 prompt decides.
local function document_changed(buf)
  local doc = docs[buf]
  if not doc or doc.locked or not api.nvim_buf_is_valid(buf) then return end
  api.nvim_buf_call(buf, function() vim.cmd('setlocal autoread') end)
  pcall(vim.cmd, 'checktime ' .. buf)
  if api.nvim_buf_is_valid(buf) then api.nvim_buf_call(buf, function() vim.cmd('setlocal autoread<') end) end
end

function M.watch(buf)
  local doc = docs[buf]
  if not doc then return end
  watch(doc.path, 'doc:' .. buf, function() document_changed(buf) end)
  if doc.threads_path and doc.watched_threads ~= doc.threads_path then
    doc.watched_threads = doc.threads_path
    watch(doc.threads_path, 'threads:' .. buf, function() threads_changed(buf) end)
  end
end

function M.unwatch(buf)
  unwatch('doc:' .. buf)
  unwatch('threads:' .. buf)
end

-- ---------------------------------------------------------------- rounds

-- Keyed by the real path, so every spelling of the file (symlinks, Windows
-- 8.3 short names) finds the same baseline.
local function baseline_path(path)
  local dir = vim.fn.stdpath('state') .. '/coauthor-baselines'
  vim.fn.mkdir(dir, 'p')
  local real = vim.uv.fs_realpath(path) or path
  return ('%s/%s-%s'):format(dir, vim.fn.sha256(real):sub(1, 16), vim.fs.basename(path))
end
M.baseline_path = baseline_path

local function shell_word(text)
  if text:match('^[%w_%-%./:\\@+,=]+$') then return text end
  return "'" .. text:gsub("'", [['\'']]) .. "'"
end

function M.prompt(path) return M.prompt_for(vim.fn.fnamemodify(path, ':.')) end

function M.prompt_for(relative)
  return ('Address the open comment threads on @%s: run `coauthor list %s` and follow its instructions.')
    :format(relative, shell_word(relative))
end

local function ai_counts(threads)
  local counts = {}
  for _, thread in ipairs(threads) do
    local n = 0
    for _, message in ipairs(thread.messages) do
      if message.author == 'ai' then n = n + 1 end
    end
    counts[thread.id] = n
  end
  return counts
end

local function plural(n, one, many) return ('%d %s'):format(n, n == 1 and one or many) end

local function summarize(buf, snapshot, before)
  local replies, edits = 0, 0
  for _, thread in ipairs(snapshot.threads or {}) do
    local seen = 0
    for _, message in ipairs(thread.messages) do
      if message.author == 'ai' then
        seen = seen + 1
        if seen > (before[thread.id] or 0) then
          replies = replies + 1
          if message.edited then edits = edits + 1 end
        end
      end
    end
  end
  return ('%s · %s · %d orphaned'):format(plural(replies, 'reply', 'replies'), plural(edits, 'edit', 'edits'),
    #M.orphans(buf))
end

-- Locks the buffer: `nomodifiable` stops edits and `readonly` stops a :w of
-- the unmodified buffer from overwriting the agent's work. Checks of the file
-- (:checktime, FocusGained) are ignored until the round ends: 'autoread' would
-- reload an unmodified buffer without asking FileChangedShell, so it is off.
local function lock(buf, doc)
  doc.round.modifiable, doc.round.readonly = vim.bo[buf].modifiable, vim.bo[buf].readonly
  vim.bo[buf].modifiable, vim.bo[buf].readonly = false, true
  api.nvim_buf_call(buf, function() vim.cmd('setlocal noautoread') end)
  doc.locked = true
end

local function unlock(buf, doc, round)
  doc.locked = false
  if api.nvim_buf_is_valid(buf) then
    vim.bo[buf].modifiable, vim.bo[buf].readonly = round.modifiable, round.readonly
    api.nvim_buf_call(buf, function() vim.cmd('setlocal autoread<') end)
  end
end

-- Ends the round: unlock, reload the document (undoable as one step, see
-- 'undoreload'), re-place anchors from what `coauthor done` saved, notify once.
function M.end_round(buf, how)
  local doc = docs[buf]
  if not doc or not doc.round then return end
  local round = doc.round
  doc.round = nil
  round.cancelled = how == 'cancelled'
  unlock(buf, doc, round)
  -- An agent that ran `coauthor done` is left to finish its last message;
  -- only a cancel stops it.
  if round.job and how == 'cancelled' then pcall(function() round.job:kill(15) end) end
  local views = {}
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    views[win] = api.nvim_win_call(win, vim.fn.winsaveview)
  end
  doc.after_reload = function(snapshot)
    for win, view in pairs(views) do
      if api.nvim_win_is_valid(win) then api.nvim_win_call(win, function() vim.fn.winrestview(view) end) end
    end
    local verb = how == 'cancelled' and 'round cancelled' or 'round done'
    notify(('%s · %s'):format(verb, summarize(buf, snapshot, round.before)))
  end
  api.nvim_buf_call(buf, function() vim.cmd('silent edit') end)
end

-- `<leader>ts`: :w, sync anchors, open the round, save the review baseline,
-- lock the buffer and yank the prompt. `opts.start(prompt, buf)` replaces the
-- yank (headless submit).
function M.submit(opts)
  opts = opts or {}
  local buf = api.nvim_get_current_buf()
  if not M.enable(buf) then return end
  local doc = docs[buf]
  if doc.round then return notify('a round is already open; :CoauthorDone or :CoauthorCancel ends it') end
  local awaiting = 0
  for _, thread in ipairs(doc.threads) do
    if thread.status == 'awaiting_ai' then awaiting = awaiting + 1 end
  end
  if awaiting == 0 then return notify('no threads are awaiting ai') end
  local ok, err = pcall(vim.cmd, 'silent write')
  if not ok then return notify(tostring(err):match('E%d+:.*') or tostring(err), vim.log.levels.ERROR) end
  -- The write's BufWritePost sync is queued ahead of this.
  M.run({ 'round', doc.path, 'open' }, function(snapshot)
    apply(buf, snapshot)
    local copied, err = vim.uv.fs_copyfile(doc.path, baseline_path(doc.path))
    if not copied then notify('could not save the review baseline: ' .. tostring(err), vim.log.levels.WARN) end
    doc.round = { before = ai_counts(doc.threads) }
    lock(buf, doc)
    local prompt = M.prompt(doc.path)
    if opts.start then
      opts.start(prompt, buf)
    else
      vim.fn.setreg(vim.fn.has('clipboard') == 1 and '+' or '"', prompt)
      notify(('round open · %s yanked; paste the prompt into your agent'):format(plural(awaiting, 'thread', 'threads')))
    end
  end)
end

-- :CoauthorDone: the manual end when the agent forgets `coauthor done`.
function M.done()
  local buf = api.nvim_get_current_buf()
  local doc = docs[buf]
  if not doc then return notify('off for this buffer (:Coauthor)') end
  if not doc.round then return notify('no round is open') end
  M.run({ 'done', doc.path }, function(snapshot) apply(buf, snapshot) end)
end

function M.cancel()
  local buf = api.nvim_get_current_buf()
  local doc = docs[buf]
  if not (doc and doc.round) then return notify('no round is open') end
  M.end_round(buf, 'cancelled')
end

-- `<leader>td`: native diff against the review baseline; again to close it.
function M.diff()
  local buf = api.nvim_get_current_buf()
  local doc = docs[buf]
  if not doc then return notify('off for this buffer (:Coauthor)') end
  if doc.diff_win and api.nvim_win_is_valid(doc.diff_win) then
    api.nvim_win_close(doc.diff_win, true)
    return
  end
  local baseline = baseline_path(doc.path)
  if not vim.uv.fs_stat(baseline) then return notify('no review baseline yet; it is saved on submit') end
  local doc_win, filetype = api.nvim_get_current_win(), vim.bo[buf].filetype
  vim.cmd('leftabove vertical new')
  local base_buf, base_win = api.nvim_get_current_buf(), api.nvim_get_current_win()
  api.nvim_buf_set_lines(base_buf, 0, -1, false, vim.fn.readfile(baseline))
  vim.bo[base_buf].buftype, vim.bo[base_buf].bufhidden, vim.bo[base_buf].swapfile = 'nofile', 'wipe', false
  vim.bo[base_buf].filetype, vim.bo[base_buf].modifiable = filetype, false
  pcall(api.nvim_buf_set_name, base_buf, 'coauthor://baseline/' .. vim.fs.basename(doc.path))
  vim.cmd('diffthis')
  api.nvim_create_autocmd('BufWipeout', {
    group = group,
    buffer = base_buf,
    once = true,
    callback = function()
      if api.nvim_win_is_valid(doc_win) then api.nvim_win_call(doc_win, function() vim.cmd('diffoff') end) end
      doc.diff_win = nil
    end,
  })
  api.nvim_set_current_win(doc_win)
  vim.cmd('diffthis')
  doc.diff_win = base_win
end

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
      local doc = docs[buf]
      if doc then
        local after = doc.after_reload
        doc.after_reload = nil
        return M.refresh(buf, { rebuild = true, done = after })
      end
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
    callback = function(event)
      local doc = docs[event.buf]
      if doc and doc.round and doc.round.job then pcall(function() doc.round.job:kill(15) end) end
      M.unwatch(event.buf)
      docs[event.buf] = nil
    end,
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
  -- During a round the file is the agent's, so a changed-file check (FocusGained,
  -- :checktime) does nothing until it ends; everywhere else 'ask' keeps
  -- Neovim's usual prompt.
  api.nvim_create_autocmd('FileChangedShell', {
    group = group,
    callback = function(event)
      local doc = docs[event.buf]
      vim.v.fcs_choice = doc and doc.round and '' or 'ask'
    end,
  })
  api.nvim_create_autocmd('ModeChanged', { group = group, callback = reanchor_mode_changed })
  -- A missed file event is caught when Neovim regains focus.
  api.nvim_create_autocmd('FocusGained', { group = group, command = 'silent! checktime' })
  api.nvim_create_user_command('Coauthor', M.toggle, { desc = 'Toggle coauthor threads for this buffer' })
  api.nvim_create_user_command('CoauthorDone', M.done, { desc = 'End the coauthor round (runs coauthor done)' })
  api.nvim_create_user_command('CoauthorCancel', M.cancel, { desc = 'End the coauthor round without waiting' })
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
  vim.keymap.set('n', '<leader>ts', function() M.submit() end,
    { desc = 'Coauthor: submit threads (save, lock, yank prompt)' })
  vim.keymap.set('n', '<leader>tS', M.submit_headless,
    { desc = 'Coauthor: submit and run the agent headless (experimental)' })
  vim.keymap.set('n', '<leader>td', M.diff, { desc = 'Coauthor: diff against the review baseline' })
  vim.keymap.set('x', '<leader>tr', M.reanchor_selection, { desc = 'Coauthor: re-anchor a thread to the selection' })
  vim.keymap.set('n', ']t', function() M.jump(1) end, { desc = 'Coauthor: next thread (else :tnext)' })
  vim.keymap.set('n', '[t', function() M.jump(-1) end, { desc = 'Coauthor: previous thread (else :tprevious)' })
end

return M
