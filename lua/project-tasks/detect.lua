-- project-tasks/detect.lua
-- Project root detection and backend selection
local M = {}

-- All known marker files (used for root detection)
M.all_markers = {
  ".project-tasks.json",
  "CMakePresets.json",
  "CMakeLists.txt",
  "pyproject.toml",
  "build.zig",
  "Cargo.toml",
  "package.json",
  "go.mod",
  "Makefile",
}

--- Find project root by looking for marker files
---@param start_path string|nil Starting path (defaults to current buffer or cwd)
---@return string|nil root Project root path
function M.find_root(start_path)
  start_path = start_path or vim.fn.expand("%:p:h")
  if start_path == "" then
    start_path = vim.fn.getcwd()
  end

  local root = vim.fs.root(start_path, M.all_markers)
  return root
end

--- Detect which backend to use based on marker files
---@param root string Project root path
---@param backends table Available backends
---@return string|nil backend_name
---@return table|nil backend
function M.get_backend(root, backends)
  -- Priority order: more specific markers first
  local priority = {
    "cmake", -- CMakePresets.json, CMakeLists.txt
    "python", -- pyproject.toml
    "zig", -- build.zig
  }

  -- Check priority backends first
  for _, name in ipairs(priority) do
    local backend = backends[name]
    if backend and M.matches_markers(root, backend.markers) then
      return name, backend
    end
  end

  -- Check remaining backends
  for name, backend in pairs(backends) do
    if backend.markers and M.matches_markers(root, backend.markers) then
      return name, backend
    end
  end

  return nil, nil
end

--- Check if any marker files exist in root
---@param root string
---@param markers table
---@return boolean
function M.matches_markers(root, markers)
  if not markers then
    return false
  end

  for _, marker in ipairs(markers) do
    local path = root .. "/" .. marker
    if vim.uv.fs_stat(path) then
      return true
    end
  end

  return false
end

--- Check if a specific marker exists
---@param root string
---@param marker string
---@return boolean
function M.has_marker(root, marker)
  return vim.uv.fs_stat(root .. "/" .. marker) ~= nil
end

return M
