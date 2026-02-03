-- Minimal init.lua for testing
-- Loads only the plugin and plenary (if available)

-- Add plugin to runtime path
vim.opt.runtimepath:prepend(vim.fn.getcwd())

-- Add tests directory to Lua path for helpers module
local tests_dir = vim.fn.getcwd() .. "/tests"
package.path = package.path .. ";" .. tests_dir .. "/?.lua"
package.path = package.path .. ";" .. tests_dir .. "/?/init.lua"

-- Disable swap files and backups for tests
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false

-- Shorter timeouts for tests
vim.opt.updatetime = 100

-- Try to load plenary for unit tests
local plenary_path = vim.fn.expand("~/.local/share/nvim/lazy/plenary.nvim")
if vim.fn.isdirectory(plenary_path) == 1 then
  vim.opt.runtimepath:append(plenary_path)
end

-- Alternative plenary locations
local alt_paths = {
  vim.fn.expand("~/.local/share/nvim/site/pack/*/start/plenary.nvim"),
  vim.fn.expand("~/.local/share/nvim/site/pack/*/opt/plenary.nvim"),
}
for _, pattern in ipairs(alt_paths) do
  local paths = vim.fn.glob(pattern, false, true)
  for _, p in ipairs(paths) do
    vim.opt.runtimepath:append(p)
  end
end

-- Test mode flag - used to capture output instead of terminal
vim.g.project_tasks_test_mode = true

-- Storage for test output
vim.g.project_tasks_last_result = nil

-- Load the plugin without keymaps
require("project-tasks").setup({
  keymaps = false,
})
