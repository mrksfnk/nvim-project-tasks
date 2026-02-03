-- project-tasks/backends.lua
-- Built-in backend definitions (data-driven)
local M = {}

-- CMake backend (with CMakePresets support)
M.cmake = {
  markers = { "CMakePresets.json", "CMakeLists.txt" },

  tasks = {
    configure = {
      -- Include -B to ensure out-of-source build when preset lacks binaryDir
      cmd = { "cmake", "--preset", "${preset}", "-B", "${binary_dir}" },
      needs_preset = true,
      -- Fallback when no presets: uses build_dir variable
      fallback_cmd = { "cmake", "-B", "${build_dir}", "-S", "." },
    },
    build = {
      cmd = { "cmake", "--build", "--preset", "${build_preset}" },
      needs_build_preset = true,  -- Special: checks for build preset
      -- Fallback when no build preset: build with binary_dir and optional target
      fallback_cmd = { "cmake", "--build", "${binary_dir}", "${target_arg}" },
      supports_build_target = true,
    },
    run = {
      cmd = { "${target_path}" },
      needs_target = true,
      args_passthrough = true,
    },
    debug = {
      cmd = { "${target_path}" },
      needs_target = true,
      args_passthrough = true,
      use_dap = true,
      dap_config = {
        type = "codelldb", -- or "cppdbg", "lldb"
        request = "launch",
      },
    },
    test = {
      cmd = { "ctest", "--preset", "${preset}" },
      needs_preset = true,
      fallback_cmd = { "ctest", "--test-dir", "${binary_dir}" },
    },
    package = {
      cmd = { "cmake", "--build", "--preset", "${build_preset}", "--target", "package" },
      needs_build_preset = true,
      fallback_cmd = { "cmake", "--build", "${binary_dir}", "--target", "package" },
    },
    clean = {
      cmd = { "rm", "-rf", "${binary_dir}" },
      needs_preset = true,
      fallback_cmd = { "rm", "-rf", "${build_dir}" },
    },
  },

  variables = {
    build_dir = "build", -- Default fallback when no presets
  },
}

-- Python/uv backend
M.python = {
  markers = { "pyproject.toml" },

  tasks = {
    run = {
      cmd = { "uv", "run", "${entry_point}" },
      args_passthrough = true,
    },
    debug = {
      cmd = { "uv", "run", "python", "-m", "debugpy", "--listen", "5678", "--wait-for-client", "${entry_point}" },
      args_passthrough = true,
      use_dap = true,
      dap_config = {
        type = "python",
        request = "attach",
        connect = { host = "127.0.0.1", port = 5678 },
      },
    },
    test = {
      cmd = { "uv", "run", "pytest" },
      args_passthrough = true,
    },
    package = {
      cmd = { "uv", "build" },
    },
  },

  variables = {
    entry_point = "src/main.py",
  },
}

return M
