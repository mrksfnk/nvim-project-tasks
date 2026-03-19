-- project-tasks/session.lua
-- Persist last selections (target, preset) per project
local M = {}

-- In-memory cache
M.data = nil
M.file_path = vim.fn.stdpath("data") .. "/project-tasks-session.json"

--- Load session data from disk
---@return table
function M.load()
  if M.data then
    return M.data
  end

  local stat = vim.uv.fs_stat(M.file_path)
  if not stat then
    M.data = {}
    return M.data
  end

  local content = vim.fn.readfile(M.file_path)
  local ok, data = pcall(vim.json.decode, table.concat(content, "\n"))
  if ok and type(data) == "table" then
    M.data = data
  else
    M.data = {}
  end

  return M.data
end

--- Save session data to disk
function M.save()
  if not M.data then
    return
  end

  local ok, json = pcall(vim.json.encode, M.data)
  if not ok then
    return
  end

  local dir = vim.fn.fnamemodify(M.file_path, ":h")
  vim.fn.mkdir(dir, "p")
  vim.fn.writefile({ json }, M.file_path)
end

--- Get a value for a project
---@param root string Project root path
---@param key string Key name (e.g., "target", "preset")
---@return any|nil
function M.get(root, key)
  local data = M.load()
  local project = data[root]
  if project then
    return project[key]
  end
  return nil
end

--- Set a value for a project
---@param root string Project root path
---@param key string Key name
---@param value any Value to store
function M.set(root, key, value)
  local data = M.load()
  if not data[root] then
    data[root] = {}
  end
  data[root][key] = value
  M.save()
end

--- Get scoped build target selection for a project/preset scope
---@param root string Project root path
---@param scope string Scope key (e.g., build preset name)
---@return string|nil value
---@return string|nil signature
function M.get_build_target(root, scope)
  local data = M.load()
  local project = data[root]
  if not project or type(project.build_targets) ~= "table" then
    return nil, nil
  end

  local entry = project.build_targets[scope]
  if type(entry) ~= "table" then
    return nil, nil
  end

  return entry.value, entry.signature
end

--- Set scoped build target selection for a project/preset scope
---@param root string Project root path
---@param scope string Scope key (e.g., build preset name)
---@param value string Target value ("" = all targets)
---@param signature string Signature for change detection
function M.set_build_target(root, scope, value, signature)
  local data = M.load()
  if not data[root] then
    data[root] = {}
  end

  if type(data[root].build_targets) ~= "table" then
    data[root].build_targets = {}
  end

  data[root].build_targets[scope] = {
    value = value,
    signature = signature,
  }
  M.save()
end

--- Clear all data for a project
---@param root string Project root path
function M.clear(root)
  local data = M.load()
  data[root] = nil
  M.save()
end

return M
