-- Test helper utilities
local M = {}

--- Get the tests directory path
---@return string
function M.tests_dir()
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(source, ":h:h")
end

--- Get path to a fixture
---@param name string Fixture name (e.g., "cmake-presets")
---@return string
function M.fixture_path(name)
  return M.tests_dir() .. "/fixtures/" .. name
end

--- Create a temporary directory
---@return string path
function M.tmpdir()
  local path = vim.fn.tempname()
  vim.fn.mkdir(path, "p")
  return path
end

--- Copy a fixture to a temporary directory
---@param fixture_name string
---@return string tmp_path
function M.copy_fixture(fixture_name)
  local src = M.fixture_path(fixture_name)
  local dst = M.tmpdir()
  vim.fn.system({ "cp", "-r", src .. "/.", dst })
  return dst
end

--- Clean up a directory
---@param path string
function M.cleanup(path)
  if path and path:match("^/tmp") then
    vim.fn.system({ "rm", "-rf", path })
  end
end

--- Wait for a condition with timeout
---@param condition function Returns true when done
---@param timeout_ms number Max wait time
---@param interval_ms number|nil Check interval (default 50)
---@return boolean success
function M.wait_for(condition, timeout_ms, interval_ms)
  interval_ms = interval_ms or 50
  local start = vim.uv.now()
  while vim.uv.now() - start < timeout_ms do
    if condition() then
      return true
    end
    vim.wait(interval_ms)
  end
  return false
end

--- Assert helper that shows diff on failure
---@param expected any
---@param actual any
---@param message string|nil
function M.assert_equals(expected, actual, message)
  if expected ~= actual then
    local msg = message or "Assertion failed"
    error(string.format("%s\nExpected: %s\nActual: %s", msg, vim.inspect(expected), vim.inspect(actual)))
  end
end

--- Assert table contains key
---@param tbl table
---@param key any
---@param message string|nil
function M.assert_has_key(tbl, key, message)
  if tbl[key] == nil then
    local msg = message or "Table missing key"
    error(string.format("%s: %s\nTable keys: %s", msg, key, vim.inspect(vim.tbl_keys(tbl))))
  end
end

--- Assert string contains substring
---@param str string
---@param substr string
---@param message string|nil
function M.assert_contains(str, substr, message)
  if not str:find(substr, 1, true) then
    local msg = message or "String does not contain substring"
    error(string.format("%s\nLooking for: %s\nIn: %s", msg, substr, str))
  end
end

return M
