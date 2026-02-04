# project-tasks.nvim

Minimal, extensible project task runner for Neovim. Run configure, build, run, debug, test, and package tasks with a unified interface.

## Features

- **Data-driven backends** — CMake and Python/uv built-in, easily add your own via config
- **CMakePresets.json** — Full support with inheritance resolution and auto-merge of `CMakeUserPresets.json`
- **CMake File API** — Automatic target discovery from build artifacts
- **Async execution** — Non-blocking tasks via `vim.system()`
- **Session memory** — Remembers last selected target/preset per project
- **nvim-dap integration** — Optional debug adapter support
- **~500 lines of code** — Simple, readable, hackable

## Requirements

- Neovim 0.10+
- Optional: [nvim-dap](https://github.com/mfussenegger/nvim-dap) for debug integration

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "your-username/project-tasks.nvim",
  version = "*",  -- Use latest release (recommended)
  config = function()
    require("project-tasks").setup({
      -- optional configuration
    })
  end,
}
```

> **Note:** Using `version = "*"` downloads only the release archive, excluding
> development files like tests. Omit this to track the main branch.

## Default Keymaps

| Key | Task | Description |
|-----|------|-------------|
| `<leader>pc` | configure | Configure project |
| `<leader>pC` | configure | Configure (select preset) |
| `<leader>pb` | build | Build project |
| `<leader>pB` | build | Build (select preset) |
| `<leader>pr` | run | Run target |
| `<leader>pR` | run | Run (select target) |
| `<leader>pd` | debug | Debug target |
| `<leader>pD` | debug | Debug (select target) |
| `<leader>pt` | test | Run tests |
| `<leader>pT` | test | Run tests (select preset) |
| `<leader>pp` | package | Package project |
| `<leader>pP` | package | Package (select preset) |
| `<leader>pe` | edit | Edit build configuration |
| `<leader>pE` | edit | Edit build configuration (select) |
| `<leader>px` | clean | Clean build artifacts |
| `<leader>pX` | clean | Clean (select preset) |
| `<leader>pQ` | cancel | Cancel running task |
| `<leader>pi` | info | Show project info |

Uppercase variants (Shift) force re-selection of target/preset.

## Commands

- `:ProjectConfigure` / `:ProjectConfigure!` (bang = prompt)
- `:ProjectBuild` / `:ProjectBuild!`
- `:ProjectRun` / `:ProjectRun!`
- `:ProjectDebug` / `:ProjectDebug!`
- `:ProjectTest` / `:ProjectTest!`
- `:ProjectPackage` / `:ProjectPackage!`
- `:ProjectEdit` / `:ProjectEdit!`
- `:ProjectClean` / `:ProjectClean!`
- `:ProjectCancel` — Cancel running task
- `:ProjectInfo` — Show detected backend and available tasks

Use `:help project-tasks` for full documentation.

## Configuration

### Plugin Setup

```lua
require("project-tasks").setup({
  -- Enable/disable default keymaps
  keymaps = true,

  -- Keymap prefix (default: "<leader>p")
  keymap_prefix = "<leader>p",

  -- Output settings
  terminal = {
    -- Output mode: "quickfix" (default), "terminal", "terminal_nofocus"
    mode = "quickfix",

    -- Terminal split settings (for terminal modes)
    position = "bottom", -- "bottom", "top", "left", "right"
    size = 15,
  },

  -- Override or extend backends
  backends = {
    -- See "Adding Backends" section
  },
})
```

### Output Modes

| Mode | Description |
|------|-------------|
| `quickfix` | **Default.** Capture output to quickfix list, stay in editor |
| `terminal_nofocus` | Split terminal, cursor stays in editor |
| `terminal` | Split terminal with focus (for interactive commands) |

### Project Configuration (`.project-tasks.json`)

Place a `.project-tasks.json` in your project root to:
- Define new backends
- Override backend settings
- Set environment variables
- Configure targets

```json
{
  "backends": {
    "zig": {
      "markers": ["build.zig"],
      "tasks": {
        "build": { "cmd": ["zig", "build"] },
        "run": { "cmd": ["zig", "build", "run"], "args_passthrough": true },
        "test": { "cmd": ["zig", "build", "test"] },
        "package": { "cmd": ["zig", "build", "-Doptimize=ReleaseSafe"] }
      }
    }
  },
  "env": {
    "MY_VAR": "value"
  },
  "variables": {
    "entry_point": "src/main.py"
  },
  "targets": {
    "my_app": {
      "path": "./build/my_app",
      "args": ["--verbose"],
      "env": { "DEBUG": "1" }
    }
  }
}
```

## Built-in Backends

### CMake

**Markers:** `CMakePresets.json`, `CMakeLists.txt`

**Tasks:**
- `configure` — `cmake --preset <preset>` (or `cmake -B <build_dir> -S .` without presets)
- `build` — `cmake --build --preset <preset>`
- `run` — Execute selected target
- `debug` — Debug with nvim-dap (codelldb by default)
- `test` — `ctest --preset <preset>`
- `package` — `cmake --build --preset <preset> --target package`
- `edit` — Edit `CMakeCache.txt` in selected build directory
- `clean` — Remove build directory

**CMakePresets Support:**
- Auto-detects `CMakePresets.json` and `CMakeUserPresets.json`
- Resolves `inherits` chains
- Expands `${sourceDir}` and `${presetName}` macros
- Extracts `binaryDir` for target discovery

### Python/uv

**Markers:** `pyproject.toml`

**Tasks:**
- `run` — `uv run <entry_point>`
- `debug` — Launch debugpy, attach with nvim-dap
- `test` — `uv run pytest`
- `package` — `uv build`
- `edit` — Edit `pyproject.toml`

**Variables:**
- `entry_point` — Default: `src/main.py`

## Adding Custom Backends

Add backends via `.project-tasks.json` or `setup()`:

```json
{
  "backends": {
    "rust": {
      "markers": ["Cargo.toml"],
      "tasks": {
        "build": { "cmd": ["cargo", "build"] },
        "run": { "cmd": ["cargo", "run"], "args_passthrough": true },
        "test": { "cmd": ["cargo", "test"] },
        "debug": {
          "cmd": ["cargo", "build"],
          "use_dap": true,
          "dap_config": {
            "type": "codelldb",
            "request": "launch"
          }
        }
      }
    }
  }
}
```

### Task Options

| Option | Type | Description |
|--------|------|-------------|
| `cmd` | `string[]` | Command to execute |
| `fallback_cmd` | `string[]` | Alternative command when preset unavailable |
| `edit_file` | `string` | File to edit (opens in Neovim) |
| `needs_preset` | `boolean` | Prompt for CMake preset selection |
| `needs_target` | `boolean` | Prompt for target selection |
| `args_passthrough` | `boolean` | Append user args to command |
| `use_dap` | `boolean` | Use nvim-dap for execution |
| `dap_config` | `table` | nvim-dap configuration |
| `env` | `table` | Task-specific environment variables |

### Variables

Use `${variable}` in commands for substitution:

| Variable | Source |
|----------|--------|
| `${preset}` | Selected CMake preset name |
| `${binary_dir}` | CMake preset's `binaryDir` |
| `${target}` | Selected target name |
| `${target_path}` | Full path to target executable |
| `${build_dir}` | Configured build directory |
| `${entry_point}` | Python entry point |

## Debug Integration

For debug tasks, install [nvim-dap](https://github.com/mfussenegger/nvim-dap) and configure adapters:

```lua
-- Example for codelldb (C/C++/Rust)
local dap = require("dap")
dap.adapters.codelldb = {
  type = "server",
  port = "${port}",
  executable = {
    command = "codelldb",
    args = { "--port", "${port}" },
  },
}
```

If nvim-dap is not available, debug tasks fall back to terminal execution.

## API

```lua
local pt = require("project-tasks")

-- Run a task
pt.run_task("build")
pt.run_task("run", { prompt = true })
pt.run_task("run", { args = { "--verbose" }, env = { DEBUG = "1" } })

-- Access configuration
pt.config.backends.cmake.tasks.build.cmd
```

## License

MIT
