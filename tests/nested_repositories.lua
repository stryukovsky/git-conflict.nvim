-- nvim --headless -u NONE -i NONE -l tests/nested_repositories.lua (from plugin root)
local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.rtp:prepend(plugin_root)
local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/nested', 'p')
local function git(repo, args, stdin)
  local result = vim.system(vim.list_extend({ 'git', '-C', repo }, args), { text = true, stdin = stdin }):wait()
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout or '')
end
local function conflict(repo, name)
  git(repo, { 'init', '-q' })
  local stage = {}
  for i, text in ipairs { 'base', 'ours', 'theirs' } do
    stage[i] = git(repo, { 'hash-object', '-w', '--stdin' }, text .. '\n')
  end
  local index = {}
  for i, hash in ipairs(stage) do index[#index + 1] = ('100644 %s %d\t%s\n'):format(hash, i, name) end
  git(repo, { 'update-index', '--index-info' }, table.concat(index))
  vim.fn.writefile({ '<<<<<<< ours', 'ours', '=======', 'theirs', '>>>>>>> theirs' }, repo .. '/' .. name)
end
conflict(root, 'outer.txt')
conflict(root .. '/nested', 'inner.txt')
-- Leave another conflicted file unopened, exercising metadata-only quickfix entries.
conflict(root .. '/nested', 'unopened.txt')
local outer = vim.fn.bufadd(root .. '/outer.txt')
local inner = vim.fn.bufadd(root .. '/nested/inner.txt')
vim.fn.bufload(outer)
vim.fn.bufload(inner)
local utils = require 'git-conflict.utils'
utils.job = function(cmd, callback)
  local result = vim.system(cmd, { text = true }):wait()
  assert(result.code == 0, result.stderr)
  callback(vim.split(vim.trim(result.stdout or ''), '\n', { trimempty = true }))
end
local plugin = require 'git-conflict'
local ns = vim.api.nvim_create_namespace('git-conflict')
local function marks(buf) return #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) end
local ok, err = xpcall(function()
  plugin.refresh(inner)
  assert(plugin.conflict_count(inner) == 1 and marks(inner) > 0, 'nested conflict not detected')
  local inner_marks = marks(inner)
  plugin.refresh(outer)
  assert(plugin.conflict_count(inner) == 1 and marks(inner) == inner_marks, 'parent refresh cleared nested conflict')
  assert(plugin.conflict_count(outer) == 1, 'parent conflict not detected')
  plugin.conflicts_to_qf_items(function(items)
    local unopened = false
    for _, item in ipairs(items) do unopened = unopened or item.filename == root .. '/nested/unopened.txt' end
    assert(unopened, 'unopened conflict missing from quickfix')
  end)
  git(root, { 'add', 'outer.txt' })
  plugin.refresh(outer)
  assert(plugin.conflict_count(outer) == 0 and marks(outer) == 0, 'resolved parent state not cleared')
  assert(plugin.conflict_count(inner) == 1 and marks(inner) == inner_marks, 'parent resolution cleared nested conflict')
  git(root .. '/nested', { 'add', 'inner.txt' })
  plugin.refresh(inner)
  assert(plugin.conflict_count(inner) == 0 and marks(inner) == 0, 'resolved nested state not cleared')
end, debug.traceback)
vim.fn.delete(root, 'rf')
assert(ok, err)
print('PASS nested repository ownership, parent/nested resolution, highlights, and unopened quickfix entries')
