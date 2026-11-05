-- Run from the host config: nvim --headless -u NONE -i NONE -n -l data/lazy/git-conflict.nvim/tests/global_mappings.lua
local root = vim.fn.getcwd()
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(root .. '/data/lazy/langmapper.nvim')
vim.opt.rtp:append(root .. '/data/lazy/git-conflict.nvim')
require('langmapper').setup { hack_keymap = false }
vim.g.mapleader = ' '
local notifications = {}
vim.notify = function(message) notifications[#notifications + 1] = message end
local utils = require 'git-conflict.utils'
utils.job = function(cmd, callback)
  local result = vim.system(cmd, { text = true }):wait()
  assert(result.code == 0, result.stderr)
  callback(vim.split(vim.trim(result.stdout or ''), '\n', { trimempty = true }))
end
local plugin = require 'git-conflict'
plugin.setup { default_mappings = false }
assert(vim.tbl_isempty(vim.fn.maparg('<leader>co', 'n', false, true)), 'disabled defaults registered a shortcut')
plugin.setup {
  default_mappings = {
    ours = '<leader>co', theirs = '<leader>ct', both = '<leader>cb', none = '<leader>c0',
    next = '<Plug>(git-conflict-next-unused)', prev = '<Plug>(git-conflict-prev-unused)',
  },
}
local function assert_global()
  for _, mode in ipairs { 'n', 'v' } do
    for _, key in ipairs { '<leader>co', '<leader>ct', '<leader>cb', '<leader>c0' } do
      local mapping = vim.fn.maparg(key, mode, false, true)
      assert(mapping.buffer == 0 and mapping.rhs:find('<Plug>', 1, true), key .. ' is not global')
    end
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(0, mode)) do
      assert(not (mapping.desc or ''):find('Git Conflict:', 1, true), 'conflict installed a buffer-local mapping')
    end
  end
end
assert_global()
local clean = vim.api.nvim_buf_get_lines(0, 0, -1, false)
for _, side in ipairs { 'ours', 'theirs', 'both', 'none', 'base' } do
  local count = #notifications
  plugin.choose(side)
  assert(#notifications == count + 1 and notifications[#notifications] == 'Not at conflict')
  assert(vim.deep_equal(clean, vim.api.nvim_buf_get_lines(0, 0, -1, false)), 'invalid choice edited clean text')
end
local original_mode = vim.fn.mode
vim.fn.mode = function() return 'v' end
local count = #notifications
plugin.choose('ours')
vim.fn.mode = original_mode
assert(vim.wait(300, function() return #notifications > count end, 10), 'visual selection without conflict did not warn')
assert(notifications[#notifications] == 'Not at conflict')
assert(vim.deep_equal(clean, vim.api.nvim_buf_get_lines(0, 0, -1, false)))
plugin.find_next('ours'); assert(notifications[#notifications] == 'Not at conflict')
plugin.find_prev('ours'); assert(notifications[#notifications] == 'Not at conflict')
local repo = vim.fn.tempname()
vim.fn.mkdir(repo, 'p')
local function git(args, stdin)
  local result = vim.system(vim.list_extend({ 'git', '-C', repo }, args), { text = true, stdin = stdin }):wait()
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout or '')
end
git { 'init', '-q' }
local index = {}
for stage, text in ipairs { 'base', 'ours', 'theirs' } do
  local hash = git({ 'hash-object', '-w', '--stdin' }, text .. '\n')
  index[#index + 1] = ('100644 %s %d\tfile.txt\n'):format(hash, stage)
end
git({ 'update-index', '--index-info' }, table.concat(index))
local lines = { 'before', '<<<<<<< ours', 'ours', '=======', 'theirs', '>>>>>>> theirs', 'after' }
vim.fn.writefile(lines, repo .. '/file.txt')
local detected, resolved = 0, 0
vim.api.nvim_create_autocmd('User', { pattern = 'GitConflictDetected', callback = function() detected = detected + 1 end })
vim.api.nvim_create_autocmd('User', { pattern = 'GitConflictResolved', callback = function() resolved = resolved + 1 end })
vim.cmd.edit(repo .. '/file.txt')
plugin.refresh()
assert_global()
plugin.refresh()
assert(detected == 1, 'unchanged conflict repeatedly emitted detection event')
vim.api.nvim_win_set_cursor(0, { 1, 0 })
plugin.choose('ours')
assert(notifications[#notifications] == 'Not at conflict', 'cursor outside conflict did not warn')
assert(vim.deep_equal(lines, vim.api.nvim_buf_get_lines(0, 0, -1, false)))
vim.api.nvim_win_set_cursor(0, { 3, 0 })
local count = #notifications
plugin.choose('ours')
assert(vim.deep_equal({ 'before', 'ours', 'after' }, vim.api.nvim_buf_get_lines(0, 0, -1, false)))
assert(#notifications == count, 'successful choice emitted missing-conflict warning')
assert(resolved == 1, 'resolution event missing')
assert_global()
vim.api.nvim_exec_autocmds('User', { pattern = 'GitConflictDetected' })
vim.api.nvim_exec_autocmds('User', { pattern = 'GitConflictResolved' })
assert_global()
vim.fn.delete(repo, 'rf')
print('PASS global Normal/Visual mappings, disabled defaults, conflict lifecycle, missing-conflict warnings, and choice behavior')
