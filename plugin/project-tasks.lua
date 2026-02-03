-- plugin/project-tasks.lua
-- Auto-load: register commands and setup on VimEnter
if vim.g.loaded_project_tasks then
  return
end
vim.g.loaded_project_tasks = true

-- Defer setup to allow user config in init.lua
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    -- Only auto-setup if user hasn't called setup() manually
    local pt = require("project-tasks")
    if not pt._setup_called then
      pt.setup()
      pt._setup_called = true
    end
  end,
  once = true,
})

-- Provide a way to check if plugin is available
vim.api.nvim_create_user_command("ProjectTasksInfo", function()
  local detect = require("project-tasks.detect")
  local pt = require("project-tasks")

  local root = detect.find_root()
  if not root then
    print("No project root found")
    return
  end

  local backend_name, backend = detect.get_backend(root, pt.config.backends)
  local tasks = backend and backend.tasks and vim.tbl_keys(backend.tasks) or {}
  table.sort(tasks)

  print("Project Tasks Info:")
  print("  Root: " .. root)
  print("  Backend: " .. (backend_name or "none"))
  print("  Tasks: " .. table.concat(tasks, ", "))
end, { desc = "Show project-tasks info" })
