local M = {}
local api = vim.api
local snapshots, history = {}, {}

local function warn(message)
  vim.notify('Diffview LSP: ' .. message, vim.log.levels.WARN)
end

local function context()
  local buf = api.nvim_get_current_buf()
  local saved = vim.b[buf].diffview_lsp
  if saved then return saved end
  local ok, lib = pcall(require, 'diffview.lib')
  local view = ok and lib.get_current_view()
  for _, win in ipairs(view and view.cur_layout and view.cur_layout.windows or {}) do
    local file = win.file
    if file and file.bufnr == buf and not file.nulled then
      if file.rev.type ~= require('diffview.vcs.rev').RevType.COMMIT then
        warn('Snapshot navigation currently supports Git commits. Use Ctrl-w gf for the working file.')
        return
      end
      return { repo = file.adapter.ctx.toplevel, commit = file.rev.commit, path = file.path }
    end
  end
  warn('No committed source file in this pane.')
end

local function snapshot(ctx, done)
  local key = ctx.repo .. '\n' .. ctx.commit
  local item = snapshots[key]
  if item then
    if item.ready then done(item) else table.insert(item.waiters, done) end
    return
  end
  item = { root = vim.fn.tempname(), waiters = { done } }
  snapshots[key] = item
  vim.uv.fs_mkdir(item.root, 448)
  item.root = vim.uv.fs_realpath(item.root) or item.root
  local archive = item.root .. '.tar'
  local function finish(err)
    vim.uv.fs_unlink(archive)
    item.ready = not err
    if err then snapshots[key] = nil; vim.fn.delete(item.root, 'rf'); warn(err) end
    for _, callback in ipairs(item.waiters) do callback(not err and item or nil) end
    item.waiters = nil
  end
  vim.notify('Diffview LSP: preparing source at ' .. ctx.commit:sub(1, 7))
  vim.system({ 'git', '-C', ctx.repo, 'archive', '--format=tar', '--output=' .. archive, ctx.commit },
    { text = true }, vim.schedule_wrap(function(result)
      if result.code ~= 0 then finish(result.stderr); return end
      vim.system({ 'tar', '-xf', archive, '-C', item.root }, { text = true }, vim.schedule_wrap(function(out)
        finish(out.code ~= 0 and out.stderr or nil)
      end))
    end))
end

local function buffer(item, ctx)
  local path = item.root .. '/' .. ctx.path
  local real = vim.uv.fs_realpath(path)
  local root = vim.uv.fs_realpath(item.root)
  if not real or real:sub(1, #root + 1) ~= root .. '/' then
    warn('Source is absent from the Git archive or points outside it: ' .. ctx.path)
    return
  end
  item.buffers = item.buffers or {}
  local buf = item.buffers[path]
  if buf and api.nvim_buf_is_valid(buf) then return buf end
  local fd = assert(vim.uv.fs_open(path, 'r', 0))
  local content = vim.uv.fs_read(fd, vim.uv.fs_fstat(fd).size, 0)
  vim.uv.fs_close(fd)
  local lines = vim.split(content:gsub('\r\n', '\n'):gsub('\n$', ''), '\n', { plain = true })
  buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_name(buf, path)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.b[buf].diffview_lsp = ctx
  vim.bo[buf].readonly = true
  vim.bo[buf].modifiable = false
  api.nvim_buf_call(buf, function() vim.cmd('noautocmd setfiletype python') end)
  M.maps(buf)
  item.buffers[path] = buf
  return buf
end

local function later_until(check, done, attempts)
  if check() then done(); return end
  if attempts == 0 then warn('Timed out waiting for source navigation. Try again.'); return end
  vim.defer_fn(function() later_until(check, done, attempts - 1) end, 25)
end

local function jump(view, item, ctx, range, encoding)
  local function place(win)
    api.nvim_set_current_win(win)
    local line = api.nvim_buf_get_lines(0, range.start.line, range.start.line + 1, false)[1] or ''
    local col = vim.str_byteindex(line, encoding, range.start.character, false)
    api.nvim_win_set_cursor(win, { range.start.line + 1, col })
    vim.cmd('normal! zv')
  end
  for _, entry in view.files:iter() do
    for _, win in ipairs(entry.layout.windows) do
      local file = win.file
      if file and file.path == ctx.path and file.rev.commit == ctx.commit and not file.nulled then
        view.emitter:once('file_open_post', function(_, opened)
          if opened ~= entry then return end
          -- Place the target after Diffview and the review reader restore their views.
          vim.schedule(function()
            vim.schedule(function()
              if api.nvim_get_current_tabpage() ~= view.tabpage or view.cur_entry ~= entry then return end
              for _, target in ipairs(view.cur_layout.windows) do
                if target.file and target.file.rev.commit == ctx.commit and target.file.path == ctx.path then
                  place(target.id)
                  return
                end
              end
            end)
          end)
        end)
        view:set_file(entry, true, true)
        return
      end
    end
  end
  local buf = buffer(item, ctx)
  if not buf then return end
  -- Unchanged files have no entry in the diff; keep their source in a separate pane.
  if view._python_lsp_source_win and api.nvim_win_is_valid(view._python_lsp_source_win) then
    api.nvim_set_current_win(view._python_lsp_source_win)
  else
    vim.cmd('botright vsplit')
    view._python_lsp_source_win = api.nvim_get_current_win()
  end
  api.nvim_win_set_buf(0, buf)
  vim.wo.winbar = ctx.path .. ' @ ' .. ctx.commit:sub(1, 7)
  vim.keymap.set('n', 'q', '<Cmd>close<CR>', { buffer = buf, desc = 'Close revision source pane' })
  place(api.nvim_get_current_win())
end

function M.request(method)
  local ctx = context()
  if not ctx then return end
  local source, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
  local cursor = api.nvim_win_get_cursor(win)
  local tick = api.nvim_buf_get_changedtick(source)
  local view = require('diffview.lib').get_current_view()
  if not view then warn('Open the source from a Diffview tab.'); return end
  local function current()
    return api.nvim_win_is_valid(win) and api.nvim_get_current_win() == win
      and api.nvim_win_get_buf(win) == source and api.nvim_buf_get_changedtick(source) == tick
      and vim.deep_equal(api.nvim_win_get_cursor(win), cursor)
  end
  snapshot(ctx, function(item)
    if not item or not current() then return end
    local buf = buffer(item, ctx)
    if not buf then return end
    if not vim.deep_equal(api.nvim_buf_get_lines(source, 0, -1, false), api.nvim_buf_get_lines(buf, 0, -1, false)) then
      warn('This buffer differs from the archived commit; navigation was cancelled.')
      return
    end
    local config = vim.deepcopy(vim.lsp.config.basedpyright)
    config.name = 'basedpyright-review'
    config.root_dir = vim.fs.root(item.root .. '/' .. ctx.path, config.root_markers) or item.root
    config.on_attach = function(_, attached)
      vim.diagnostic.enable(false, { bufnr = attached })
      M.maps(attached)
    end
    local id = vim.lsp.start(config, { bufnr = buf })
    local client = id and vim.lsp.get_client_by_id(id)
    if not client then warn('Could not start BasedPyright.'); return end
    later_until(function() return client.initialized or client:is_stopped() end, function()
      if not current() or client:is_stopped() then return end
      local params = vim.lsp.util.make_position_params(win, client.offset_encoding)
      params.textDocument.uri = vim.uri_from_bufnr(buf)
      if method == 'textDocument/references' then params.context = { includeDeclaration = true } end
      client:request(method, params, function(err, result)
        if not current() then return end
        if err then warn(err.message); return end
        if not result or vim.tbl_isempty(result) then warn('No result at this position.'); return end
        if method == 'textDocument/hover' then
          local lines = vim.lsp.util.convert_input_to_markdown_lines(result.contents)
          vim.lsp.util.open_floating_preview(lines, 'markdown', { border = 'single' })
          return
        end
        local locations = result.uri and { result } or result
        local label = method == 'textDocument/references' and 'References' or 'Definition'
        local function select(target)
          if not target or not current() then return end
          local path = vim.uri_to_fname(target.uri or target.targetUri)
          if path:sub(1, #item.root + 1) ~= item.root .. '/' then
            warn(label .. ' outside this commit: ' .. path)
            return
          end
          history[view.tabpage] = history[view.tabpage] or {}
          table.insert(history[view.tabpage], { ctx = ctx, item = item, cursor = cursor, win = win, buf = source })
          jump(view, item, { repo = ctx.repo, commit = ctx.commit, path = path:sub(#item.root + 2) },
            target.targetSelectionRange or target.range, client.offset_encoding)
        end
        if #locations == 1 then select(locations[1]) else
          vim.ui.select(locations, { prompt = label .. ' at ' .. ctx.commit:sub(1, 7), format_item = function(loc)
            local path = vim.uri_to_fname(loc.uri or loc.targetUri)
            if path:sub(1, #item.root + 1) == item.root .. '/' then path = path:sub(#item.root + 2) end
            local start = (loc.targetSelectionRange or loc.range).start
            return ('%s:%d:%d'):format(path, start.line + 1, start.character + 1)
          end }, select)
        end
      end, buf)
    end, 600)
  end)
end

function M.back()
  local view = require('diffview.lib').get_current_view()
  local stack = view and history[view.tabpage]
  local target = stack and table.remove(stack)
  if not target then warn('No previous source jump in this review.'); return end
  if api.nvim_win_is_valid(target.win) and api.nvim_win_get_buf(target.win) == target.buf then
    api.nvim_set_current_win(target.win)
    api.nvim_win_set_cursor(target.win, target.cursor)
  else
    jump(view, target.item, target.ctx, { start = { line = target.cursor[1] - 1, character = target.cursor[2] } }, 'utf-8')
  end
end

function M.maps(buf)
  vim.keymap.set('n', 'gd', function() M.request('textDocument/definition') end,
    { buffer = buf, desc = 'Diffview LSP: definition at this commit' })
  vim.keymap.set('n', 'K', function() M.request('textDocument/hover') end,
    { buffer = buf, desc = 'Diffview LSP: hover at this commit' })
  vim.keymap.set('n', 'grr', function() M.request('textDocument/references') end,
    { buffer = buf, desc = 'Diffview LSP: references at this commit' })
  vim.keymap.set('n', '<C-t>', M.back, { buffer = buf, desc = 'Diffview LSP: return from source jump' })
end

function M.setup()
  api.nvim_create_autocmd('FileType', {
    group = api.nvim_create_augroup('diffview_python_lsp', { clear = true }),
    pattern = 'python',
    callback = function(args)
      if api.nvim_buf_get_name(args.buf):sub(1, 11) == 'diffview://' then M.maps(args.buf) end
    end,
  })
end

return M
