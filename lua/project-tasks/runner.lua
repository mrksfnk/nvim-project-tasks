-- project-tasks/runner.lua
-- Async task execution with variable expansion and terminal output
local M = {}

-- Active terminal buffer/window
M.term_buf = nil
M.term_win = nil

--- Expand ${var} placeholders in a string
---@param str string
---@param variables table
---@return string
function M.expand_var(str, variables)
  return (str:gsub("%${([^}]+)}", function(var)
    return variables[var] or ""
  end))
end

--- Expand variables in command array
---@param cmd table
---@param variables table
---@return table
function M.expand_cmd(cmd, variables)
  local result = {}
  for _, part in ipairs(cmd) do
    local expanded = M.expand_var(part, variables)
    -- Only include non-empty parts
    if expanded ~= "" then
      table.insert(result, expanded)
    end
  end
  return result
end

--- Build the final command from task definition
---@param task table
---@param ctx table
---@return table|nil cmd
function M.build_command(task, ctx)
  local cmd = task.cmd

  -- Use fallback_cmd if:
  -- 1. needs_preset and no preset variable set, OR
  -- 2. needs_build_preset and no build_preset variable set
  local use_fallback = false
  if task.fallback_cmd then
    if task.needs_preset and not ctx.variables.preset then
      use_fallback = true
    elseif task.needs_build_preset and not ctx.variables.build_preset then
      use_fallback = true
    end
  end

  if use_fallback then
    cmd = task.fallback_cmd
  end

  if not cmd then
    return nil
  end

  -- Expand variables
  local expanded = M.expand_cmd(cmd, ctx.variables)

  -- Append passthrough args
  if task.args_passthrough and ctx.args then
    for _, arg in ipairs(ctx.args) do
      table.insert(expanded, arg)
    end
  end

  return expanded
end

--- Check if a CMake build directory is properly configured
---@param root string Project root
---@param binary_dir string Build directory (relative or absolute)
---@return boolean
function M.is_cmake_configured(root, binary_dir)
  if not binary_dir or binary_dir == "" then
    return false
  end
  -- Make path absolute if relative
  local build_path = binary_dir
  if not vim.startswith(binary_dir, "/") then
    build_path = root .. "/" .. binary_dir
  end
  local cache_path = build_path .. "/CMakeCache.txt"
  return vim.uv.fs_stat(cache_path) ~= nil
end

--- Run a task in the terminal
---@param task table
---@param ctx table
---@param terminal_opts table
function M.run(task, ctx, terminal_opts)
  -- Validate required variables for build tasks
  if task.needs_build_preset and not ctx.variables.build_preset then
    -- Using fallback, need binary_dir
    if not ctx.variables.binary_dir or ctx.variables.binary_dir == "" then
      vim.notify("[project-tasks] No build directory found. Run configure first.", vim.log.levels.ERROR)
      return
    end
    -- Check if the build directory is properly configured
    if ctx.backend == "cmake" and not M.is_cmake_configured(ctx.root, ctx.variables.binary_dir) then
      vim.notify(
        ("[project-tasks] Build directory '%s' not configured. Run configure first (\\<leader\\>pc)."):format(
          ctx.variables.binary_dir
        ),
        vim.log.levels.ERROR
      )
      return
    end
  end

  local cmd = M.build_command(task, ctx)

  if not cmd or #cmd == 0 then
    vim.notify("[project-tasks] Could not build command", vim.log.levels.ERROR)
    return
  end

  -- Check for dap integration
  if task.use_dap then
    local ok = M.try_dap(task, ctx, cmd)
    if ok then
      return
    end
    -- Fall through to terminal execution
  end

  -- Determine output mode
  terminal_opts = terminal_opts or {}
  local mode = terminal_opts.mode or "quickfix"

  if mode == "terminal" then
    M.run_in_terminal(cmd, ctx, terminal_opts, true)
  elseif mode == "terminal_nofocus" then
    M.run_in_terminal(cmd, ctx, terminal_opts, false)
  else
    -- Default: quickfix
    M.run_to_quickfix(cmd, ctx, terminal_opts)
  end
end

--- Try to launch via nvim-dap
---@param task table
---@param ctx table
---@param cmd table
---@return boolean success
function M.try_dap(task, ctx, cmd)
  local ok, dap = pcall(require, "dap")
  if not ok then
    vim.notify("[project-tasks] nvim-dap not available, falling back to terminal", vim.log.levels.INFO)
    return false
  end

  if not task.dap_config then
    return false
  end

  local config = vim.deepcopy(task.dap_config)

  -- Set program path
  if ctx.variables.target_path then
    config.program = ctx.variables.target_path
  elseif cmd[1] then
    config.program = cmd[1]
  end

  -- Set working directory
  config.cwd = ctx.root

  -- Set arguments
  if ctx.args and #ctx.args > 0 then
    config.args = ctx.args
  end

  -- Set environment
  if ctx.env and next(ctx.env) then
    config.env = ctx.env
  end

  dap.run(config)
  return true
end

--- Run command in terminal buffer
---@param cmd table
---@param ctx table
---@param terminal_opts table
---@param focus boolean Whether to focus the terminal
function M.run_in_terminal(cmd, ctx, terminal_opts, focus)
  terminal_opts = terminal_opts or {}
  local position = terminal_opts.position or "bottom"
  local size = terminal_opts.size or 15

  -- Build shell command string
  local cmd_str = table.concat(vim.tbl_map(vim.fn.shellescape, cmd), " ")

  -- Add environment variables
  local env_str = ""
  if ctx.env and next(ctx.env) then
    local env_parts = {}
    for k, v in pairs(ctx.env) do
      table.insert(env_parts, k .. "=" .. vim.fn.shellescape(v))
    end
    env_str = table.concat(env_parts, " ") .. " "
  end

  local full_cmd = env_str .. cmd_str

  -- Save current window to restore if not focusing
  local current_win = vim.api.nvim_get_current_win()

  -- Create or reuse terminal window
  M.ensure_terminal(position, size)

  -- Send command to terminal
  vim.fn.chansend(vim.b[M.term_buf].terminal_job_id, full_cmd .. "\n")

  -- Focus terminal or return to previous window
  if focus then
    vim.api.nvim_set_current_win(M.term_win)
    vim.cmd("startinsert")
  else
    vim.api.nvim_set_current_win(current_win)
  end

  -- Show notification
  vim.notify(("[project-tasks] Running: %s"):format(cmd[1] or "command"), vim.log.levels.INFO)
end

--- Ensure terminal buffer and window exist
---@param position string
---@param size number
function M.ensure_terminal(position, size)
  -- Check if existing terminal is still valid
  if M.term_buf and vim.api.nvim_buf_is_valid(M.term_buf) then
    -- Find or create window for it
    if M.term_win and vim.api.nvim_win_is_valid(M.term_win) then
      return
    end
    -- Buffer exists but window doesn't - create window
    M.open_terminal_window(position, size)
    vim.api.nvim_win_set_buf(M.term_win, M.term_buf)
    return
  end

  -- Create new terminal
  M.open_terminal_window(position, size)
  M.term_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(M.term_win, M.term_buf)
  vim.fn.termopen(vim.o.shell, {
    cwd = vim.fn.getcwd(),
  })
end

--- Open terminal window in specified position
---@param position string
---@param size number
function M.open_terminal_window(position, size)
  local cmd_map = {
    bottom = "botright " .. size .. "split",
    top = "topleft " .. size .. "split",
    right = "botright " .. size .. "vsplit",
    left = "topleft " .. size .. "vsplit",
  }

  vim.cmd(cmd_map[position] or cmd_map.bottom)
  M.term_win = vim.api.nvim_get_current_win()
end

--- Run command and capture output to quickfix list (with streaming)
---@param cmd table
---@param ctx table
---@param opts table
function M.run_to_quickfix(cmd, ctx, opts)
  local cmd_name = cmd[1] or "command"
  local cmd_str = table.concat(cmd, " ")

  -- Immediately show quickfix with "Running..." status
  vim.fn.setqflist({}, "r", {
    title = cmd_name .. " (running...)",
    items = { { text = "$ " .. cmd_str }, { text = "" } },
  })
  vim.cmd("copen")
  vim.notify(("[project-tasks] Running: %s"):format(cmd_name), vim.log.levels.INFO)

  -- Collect output lines for streaming to quickfix
  local lines = {}
  local function append_output(err, data)
    if err or not data then
      return
    end
    local new_lines = vim.split(data, "\n", { trimempty = false })
    for _, line in ipairs(new_lines) do
      if line ~= "" then
        table.insert(lines, line)
      end
    end
    -- Update quickfix with current output
    vim.schedule(function()
      local qf_items = { { text = "$ " .. cmd_str }, { text = "" } }
      for _, l in ipairs(lines) do
        table.insert(qf_items, { text = l })
      end
      vim.fn.setqflist({}, "r", { title = cmd_name .. " (running...)", items = qf_items })
      -- Scroll to bottom
      vim.cmd("cbottom")
    end)
  end

  vim.system(cmd, {
    cwd = ctx.root,
    env = ctx.env,
    text = true,
    stdout = append_output,
    stderr = append_output,
  }, function(result)
    vim.schedule(function()
      -- Final update with completion status
      local qf_items = { { text = "$ " .. cmd_str }, { text = "" } }
      for _, l in ipairs(lines) do
        table.insert(qf_items, { text = l })
      end

      local status_icon = result.code == 0 and "✓" or "✗"
      local status_text = result.code == 0 and "completed" or ("failed (exit %d)"):format(result.code)
      table.insert(qf_items, { text = "" })
      table.insert(qf_items, { text = ("[%s %s %s]"):format(status_icon, cmd_name, status_text) })

      vim.fn.setqflist({}, "r", { title = cmd_name .. " " .. status_icon, items = qf_items })
      vim.cmd("cbottom")

      if result.code == 0 then
        vim.notify(("[project-tasks] ✓ %s completed"):format(cmd_name), vim.log.levels.INFO)
      else
        vim.notify(("[project-tasks] ✗ %s failed (exit %d)"):format(cmd_name, result.code), vim.log.levels.ERROR)
      end
    end)
  end)
end

return M
