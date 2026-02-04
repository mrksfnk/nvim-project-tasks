-- project-tasks.nvim
-- Minimal, extensible project task runner for Neovim
local M = {}

local detect = require("project-tasks.detect")
local runner = require("project-tasks.runner")
local session = require("project-tasks.session")

M.config = {
  backends = {},
  keymaps = true,
  keymap_prefix = "<leader>p",
  terminal = {
    position = "bottom",
    size = 15,
  },
}

--- Merge user config with defaults
---@param opts table|nil
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  -- Load built-in backends
  local builtin = require("project-tasks.backends")
  for name, backend in pairs(builtin) do
    if not M.config.backends[name] then
      M.config.backends[name] = backend
    end
  end

  -- Load project-local config if exists
  M.load_project_config()

  -- Setup keymaps if enabled
  if M.config.keymaps then
    M.setup_keymaps()
  end

  -- Setup commands
  M.setup_commands()
end

--- Load .project-tasks.json from project root
function M.load_project_config()
  local root = detect.find_root()
  if not root then
    return
  end

  local config_path = root .. "/.project-tasks.json"
  local stat = vim.uv.fs_stat(config_path)
  if not stat then
    return
  end

  local content = vim.fn.readfile(config_path)
  local ok, data = pcall(vim.json.decode, table.concat(content, "\n"))
  if not ok then
    vim.notify("[project-tasks] Invalid .project-tasks.json", vim.log.levels.ERROR)
    return
  end

  -- Merge backends
  if data.backends then
    for name, backend in pairs(data.backends) do
      M.config.backends[name] = vim.tbl_deep_extend("force", M.config.backends[name] or {}, backend)
    end
  end

  -- Store project-level overrides
  M.config.project = data
end

--- Run a task by name
---@param task_name string
---@param opts table|nil { prompt = bool, args = table, env = table }
function M.run_task(task_name, opts)
  opts = opts or {}

  -- Special handling for cancel task
  if task_name == "cancel" then
    runner.cancel()
    return
  end

  local root = detect.find_root()
  if not root then
    vim.notify("[project-tasks] No project root found", vim.log.levels.WARN)
    return
  end

  local backend_name, backend = detect.get_backend(root, M.config.backends)
  if not backend then
    vim.notify("[project-tasks] No backend detected for this project", vim.log.levels.WARN)
    return
  end

  local task = backend.tasks and backend.tasks[task_name]
  if not task then
    vim.notify(("[project-tasks] Task '%s' not available for %s"):format(task_name, backend_name), vim.log.levels.INFO)
    return
  end

  -- Build context with variables
  local ctx = {
    root = root,
    backend = backend_name,
    task = task_name,
    env = vim.tbl_extend("force", backend.env or {}, M.config.project and M.config.project.env or {}, opts.env or {}),
    args = opts.args or {},
    variables = vim.tbl_extend("force", backend.variables or {}, M.config.project and M.config.project.variables or {}),
  }

  -- Handle preset selection for CMake
  if task.needs_preset then
    M.select_preset(ctx, opts.prompt, function(preset)
      if preset then
        ctx.variables.preset = preset.name
        ctx.variables.binary_dir = preset.binaryDir
        M.continue_task(task, ctx, opts)
      elseif task.fallback_cmd then
        -- No presets available but task has a fallback - continue anyway
        M.continue_task(task, ctx, opts)
      end
      -- Otherwise we already notified about no presets
    end)
    return
  end

  -- Handle build preset selection (separate from configure presets)
  if task.needs_build_preset then
    local presets_mod = require("project-tasks.presets")
    M.ensure_preset_loaded(ctx, function()
      if presets_mod.has_build_preset(ctx.root) then
        -- Has build presets, use build preset selection
        M.select_build_preset(ctx, opts.prompt, function(build_preset)
          if build_preset then
            ctx.variables.build_preset = build_preset.name
            -- Allow target selection when building with preset
            if task.supports_build_target and opts.prompt then
              M.select_build_target(ctx, function(target)
                if target and target ~= "" then
                  ctx.variables.target_arg = "--target " .. target
                else
                  ctx.variables.target_arg = ""
                end
                M.continue_task(task, ctx, opts)
              end)
            else
              ctx.variables.target_arg = ""
              M.continue_task(task, ctx, opts)
            end
          elseif task.fallback_cmd then
            -- No build preset selected but task has fallback
            M.continue_task(task, ctx, opts)
          end
        end)
      elseif task.fallback_cmd then
        -- No build presets defined, use fallback with optional target selection
        if task.supports_build_target then
          M.select_build_target(ctx, function(target)
            if target and target ~= "" then
              ctx.variables.target_arg = "--target " .. target
            else
              ctx.variables.target_arg = ""
            end
            M.continue_task(task, ctx, opts)
          end)
        else
          ctx.variables.target_arg = ""
          M.continue_task(task, ctx, opts)
        end
      end
    end)
    return
  end

  -- Handle target selection
  if task.needs_target then
    -- For CMake, we need the preset to know binary_dir for target discovery
    if backend_name == "cmake" then
      M.ensure_preset_loaded(ctx, function()
        M.select_target(ctx, opts.prompt, function(target)
          if not target then
            return
          end
          ctx.variables.target = target.name
          ctx.variables.target_path = target.path
          M.continue_task(task, ctx, opts)
        end)
      end)
    else
      M.select_target(ctx, opts.prompt, function(target)
        if not target then
          return
        end
        ctx.variables.target = target.name
        ctx.variables.target_path = target.path
        M.continue_task(task, ctx, opts)
      end)
    end
    return
  end

  M.continue_task(task, ctx, opts)
end

--- Continue task execution after selections
---@param task table
---@param ctx table
---@param opts table
function M.continue_task(task, ctx, opts)
  -- Special handling for edit_config task - open file directly in Neovim
  if task.edit_file then
    local file_path = runner.expand_var(task.edit_file, ctx.variables)
    if not vim.startswith(file_path, "/") then
      file_path = ctx.root .. "/" .. file_path
    end
    vim.cmd("edit " .. file_path)
    return
  end

  -- Merge task-specific env
  if task.env then
    ctx.env = vim.tbl_extend("force", ctx.env, task.env)
  end

  runner.run(task, ctx, M.config.terminal)
end

--- Ensure preset is loaded into context (from session, without prompting)
--- Used when we need binary_dir for target discovery
---@param ctx table
---@param callback function
function M.ensure_preset_loaded(ctx, callback)
  local presets_mod = require("project-tasks.presets")
  local presets = presets_mod.load(ctx.root)

  if not presets or #presets == 0 then
    -- No presets, use fallback build dir
    ctx.variables.binary_dir = ctx.variables.build_dir or "build"
    callback()
    return
  end

  -- Check session for last selection
  local last = session.get(ctx.root, "preset")
  if last then
    for _, p in ipairs(presets) do
      if p.name == last then
        ctx.variables.preset = p.name
        ctx.variables.binary_dir = p.binaryDir or ctx.variables.build_dir or "build"
        callback()
        return
      end
    end
  end

  -- No preset in session, prompt for selection
  M.select_preset(ctx, false, function(preset)
    if preset then
      ctx.variables.preset = preset.name
      ctx.variables.binary_dir = preset.binaryDir or ctx.variables.build_dir or "build"
    else
      -- User cancelled or no preset - use fallback build dir
      ctx.variables.binary_dir = ctx.variables.binary_dir or ctx.variables.build_dir or "build"
    end
    callback()
  end)
end

--- Select a CMake preset
---@param ctx table
---@param force_prompt boolean|nil
---@param callback function
function M.select_preset(ctx, force_prompt, callback)
  local presets_mod = require("project-tasks.presets")
  local presets = presets_mod.load(ctx.root)

  if not presets or #presets == 0 then
    vim.notify("[project-tasks] No CMake presets found", vim.log.levels.WARN)
    callback(nil)
    return
  end

  -- Check session for last selection
  local last = session.get(ctx.root, "preset")
  if last and not force_prompt then
    for _, p in ipairs(presets) do
      if p.name == last then
        callback(p)
        return
      end
    end
  end

  vim.ui.select(presets, {
    prompt = "Select preset:",
    format_item = function(p)
      return p.name .. (p.displayName and (" - " .. p.displayName) or "")
    end,
  }, function(choice)
    if choice then
      session.set(ctx.root, "preset", choice.name)
    end
    callback(choice)
  end)
end

--- Select a CMake build preset
---@param ctx table
---@param force_prompt boolean|nil
---@param callback function
function M.select_build_preset(ctx, force_prompt, callback)
  local presets_mod = require("project-tasks.presets")
  local build_presets = presets_mod.get_build_presets(ctx.root)

  if not build_presets or #build_presets == 0 then
    callback(nil)
    return
  end

  -- Check session for last selection
  local last = session.get(ctx.root, "build_preset")
  if last and not force_prompt then
    for _, p in ipairs(build_presets) do
      if p.name == last then
        callback(p)
        return
      end
    end
  end

  vim.ui.select(build_presets, {
    prompt = "Select build preset:",
    format_item = function(p)
      return p.name .. (p.displayName and (" - " .. p.displayName) or "")
    end,
  }, function(choice)
    if choice then
      session.set(ctx.root, "build_preset", choice.name)
    end
    callback(choice)
  end)
end

--- Select a build target (for cmake --build ... --target)
--- Uses CMake File API targets for discovery
---@param ctx table
---@param callback function
function M.select_build_target(ctx, callback)
  local presets_mod = require("project-tasks.presets")
  local targets = presets_mod.get_targets(ctx.root, ctx.variables.binary_dir)

  -- Add option for "all" (default, empty)
  local choices = { { name = "(all targets)", value = "" } }
  if targets and #targets > 0 then
    for _, t in ipairs(targets) do
      table.insert(choices, { name = t.name, value = t.name })
    end
  end

  -- Check session for last selection (nil means not set, empty string means "all")
  local last = session.get(ctx.root, "build_target")
  if last ~= nil then
    -- If it's empty string, it means "all targets" - always valid
    if last == "" then
      callback(last)
      return
    end
    -- For specific target names, check if in choices OR just use it directly
    -- (allows manually set targets even before File API discovery)
    for _, c in ipairs(choices) do
      if c.value == last then
        callback(last)
        return
      end
    end
    -- Not in choices but user explicitly set it - trust them
    if #choices <= 1 then
      -- No targets discovered yet, use the session value directly
      callback(last)
      return
    end
  end

  vim.ui.select(choices, {
    prompt = "Select build target:",
    format_item = function(c)
      return c.name
    end,
  }, function(choice)
    if choice then
      session.set(ctx.root, "build_target", choice.value)
      callback(choice.value)
    else
      callback("")
    end
  end)
end

--- Select a run target
---@param ctx table
---@param force_prompt boolean|nil
---@param callback function
function M.select_target(ctx, force_prompt, callback)
  local targets = M.get_targets(ctx)

  if not targets or #targets == 0 then
    vim.notify("[project-tasks] No targets found. Run configure first?", vim.log.levels.WARN)
    callback(nil)
    return
  end

  -- Check session for last selection
  local last = session.get(ctx.root, "target")
  if last and not force_prompt then
    for _, t in ipairs(targets) do
      if t.name == last then
        callback(t)
        return
      end
    end
  end

  vim.ui.select(targets, {
    prompt = "Select target:",
    format_item = function(t)
      return t.name
    end,
  }, function(choice)
    if choice then
      session.set(ctx.root, "target", choice.name)
    end
    callback(choice)
  end)
end

--- Get available targets for current backend
---@param ctx table
---@return table|nil
function M.get_targets(ctx)
  if ctx.backend == "cmake" then
    local presets = require("project-tasks.presets")
    local binary_dir = ctx.variables.binary_dir
    if binary_dir then
      return presets.get_targets(ctx.root, binary_dir)
    end
  end

  -- Check project config for explicit targets
  if M.config.project and M.config.project.targets then
    local targets = {}
    for name, cfg in pairs(M.config.project.targets) do
      table.insert(targets, { name = name, path = cfg.path, args = cfg.args, env = cfg.env })
    end
    return targets
  end

  return nil
end

--- Setup default keymaps
function M.setup_keymaps()
  local prefix = M.config.keymap_prefix
  local tasks = {
    { key = "c", task = "configure", desc = "Configure" },
    { key = "b", task = "build", desc = "Build" },
    { key = "r", task = "run", desc = "Run" },
    { key = "d", task = "debug", desc = "Debug" },
    { key = "t", task = "test", desc = "Test" },
    { key = "p", task = "package", desc = "Package" },
    { key = "x", task = "clean", desc = "Clean" },
    { key = "e", task = "edit", desc = "Edit Config" },
  }

  for _, t in ipairs(tasks) do
    -- Normal: use last selection
    vim.keymap.set("n", prefix .. t.key, function()
      M.run_task(t.task)
    end, { desc = "Project: " .. t.desc })

    -- Shift: force prompt
    vim.keymap.set("n", prefix .. string.upper(t.key), function()
      M.run_task(t.task, { prompt = true })
    end, { desc = "Project: " .. t.desc .. " (select)" })
  end

  -- Cancel keymap (no shift variant, Q for "quit")
  vim.keymap.set("n", prefix .. "Q", function()
    M.run_task("cancel")
  end, { desc = "Project: Cancel" })

  -- Info keymap
  vim.keymap.set("n", prefix .. "i", function()
    M.show_info()
  end, { desc = "Project: Info" })
end

--- Setup user commands
function M.setup_commands()
  local tasks = { "configure", "build", "run", "debug", "test", "package", "clean", "edit", "cancel" }

  for _, task in ipairs(tasks) do
    local cmd_name = "Project" .. task:sub(1, 1):upper() .. task:sub(2)
    vim.api.nvim_create_user_command(cmd_name, function(cmd_opts)
      local prompt = cmd_opts.bang
      M.run_task(task, { prompt = prompt })
    end, { bang = true, desc = "Project: " .. task })
  end

  vim.api.nvim_create_user_command("ProjectInfo", function()
    M.show_info()
  end, { desc = "Project: Show project info" })
end

--- Show project info (legacy command)
function M.show_info()
  local root = detect.find_root()
  local backend = root and detect.get_backend(root, M.config.backends) or nil

  local lines = {
    "Project root: " .. (root or "Not detected"),
    "Backend: " .. (backend or "None"),
  }

  if backend and M.config.backends[backend] then
    local tasks = {}
    for name, _ in pairs(M.config.backends[backend].tasks or {}) do
      table.insert(tasks, name)
    end
    table.sort(tasks)
    table.insert(lines, "Tasks: " .. table.concat(tasks, ", "))
  end

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

return M
