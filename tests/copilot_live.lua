-- Runs the real, authenticated Copilot CLI (uses AI credits), so it is not part of `make test`.
-- It guards the CLI contract the bridge relies on: sessions follow COPILOT_HOME.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
if vim.fn.executable('copilot') == 0 then
  print('SKIP: copilot is not installed.')
  vim.cmd('qa!')
end
local temp = vim.fn.tempname()
local user_home = vim.env.COPILOT_HOME or vim.fs.joinpath(vim.env.HOME, '.copilot')
local function user_sessions() return #vim.fn.glob(user_home .. '/session-state/*', true, true) end
local sessions_before = user_sessions()
local had_settings = vim.uv.fs_stat(user_home .. '/settings.json') ~= nil

vim.fn.mkdir(temp .. '/repo/.git', 'p')
vim.fn.writefile({ 'local answer = 6 * 7' }, temp .. '/repo/example.lua')
vim.env.XDG_CONFIG_HOME = temp .. '/config'
vim.g.review_context_provider = nil
local bridge = require('config.review_context')
bridge.setup()
vim.cmd.edit(temp .. '/repo/example.lua')
bridge.explain('line')

local function wait_for_answer(what)
  vim.wait(500)
  assert(vim.wait(300000, function()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(buf):match('^review%-context://') then
        local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
        if text:find('unavailable') or text:find('Could not start') or text:find('No explanation') then error(text) end
        if text:find('Meaning') then return true end
      end
    end
  end, 200), 'Copilot did not answer ' .. what)
end
wait_for_answer('without tools')
-- Read-tool mode must also work from a home Copilot has never seen this folder in.
bridge.explain('line', true)
wait_for_answer('with read tools')

local homes = vim.fn.glob(vim.fn.stdpath('config') .. '/copilot-homes/*', true, true)
assert(#homes == 1 and vim.startswith(vim.fs.basename(homes[1]), 'repo-'), 'Copilot home is not per workspace')
assert(#vim.fn.glob(homes[1] .. '/session-state/*', true, true) == 2, 'Copilot no longer saves its session under COPILOT_HOME')
assert(user_sessions() == sessions_before, 'bridge session leaked into the user Copilot home')
assert((vim.uv.fs_stat(homes[1] .. '/settings.json') ~= nil) == had_settings, 'settings.json seeding does not match the user home')

vim.cmd('ReviewCopilotHome recreate')
assert(not vim.uv.fs_stat(homes[1] .. '/session-state'), 'recreate kept bridge sessions')
vim.cmd('ReviewCopilotHome remove')
assert(not vim.uv.fs_stat(homes[1]), 'remove left the workspace home')

print('PASS: real Copilot CLI answers from a per-workspace home with and without read tools; sessions stay out of the user home; recreate and remove work.')
vim.cmd('qa!')
