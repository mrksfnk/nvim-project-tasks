-- Unit tests for project-tasks/runner.lua
local runner = require("project-tasks.runner")

describe("runner", function()
  describe("expand_var", function()
    it("expands single variable", function()
      local result = runner.expand_var("${target}", { target = "my_app" })
      assert.equals("my_app", result)
    end)

    it("expands multiple variables", function()
      local result = runner.expand_var("${binary_dir}/${target}", {
        binary_dir = "build",
        target = "app",
      })
      assert.equals("build/app", result)
    end)

    it("replaces undefined variables with empty string", function()
      local result = runner.expand_var("prefix_${undefined}_suffix", {})
      assert.equals("prefix__suffix", result)
    end)

    it("preserves text without variables", function()
      local result = runner.expand_var("cmake --build", {})
      assert.equals("cmake --build", result)
    end)
  end)

  describe("expand_cmd", function()
    it("expands variables in command array", function()
      local cmd = { "cmake", "--build", "${binary_dir}" }
      local result = runner.expand_cmd(cmd, { binary_dir = "build/debug" })
      assert.same({ "cmake", "--build", "build/debug" }, result)
    end)

    it("removes empty parts from command", function()
      local cmd = { "cmake", "${empty}", "--build" }
      local result = runner.expand_cmd(cmd, {})
      assert.same({ "cmake", "--build" }, result)
    end)

    it("handles complex command", function()
      local cmd = { "${binary_dir}/${target}" }
      local result = runner.expand_cmd(cmd, {
        binary_dir = "/project/build",
        target = "my_app",
      })
      assert.same({ "/project/build/my_app" }, result)
    end)
  end)

  describe("build_command", function()
    it("builds command from task definition", function()
      local task = { cmd = { "cmake", "--build", "${binary_dir}" } }
      local ctx = { variables = { binary_dir = "build" }, args = {} }
      local result = runner.build_command(task, ctx)
      assert.same({ "cmake", "--build", "build" }, result)
    end)

    it("uses fallback_cmd when preset not available", function()
      local task = {
        cmd = { "cmake", "--preset", "${preset}" },
        fallback_cmd = { "cmake", "-B", "${build_dir}", "-S", "." },
        needs_preset = true,
      }
      local ctx = { variables = { build_dir = "build" }, args = {} }
      local result = runner.build_command(task, ctx)
      assert.same({ "cmake", "-B", "build", "-S", "." }, result)
    end)

    it("uses cmd when preset is available", function()
      local task = {
        cmd = { "cmake", "--preset", "${preset}" },
        fallback_cmd = { "cmake", "-B", "${build_dir}", "-S", "." },
        needs_preset = true,
      }
      local ctx = { variables = { preset = "debug" }, args = {} }
      local result = runner.build_command(task, ctx)
      assert.same({ "cmake", "--preset", "debug" }, result)
    end)

    it("uses fallback_cmd when build_preset not available", function()
      local task = {
        cmd = { "cmake", "--build", "--preset", "${build_preset}" },
        fallback_cmd = { "cmake", "--build", "${binary_dir}" },
        needs_build_preset = true,
      }
      local ctx = { variables = { binary_dir = "build/debug" }, args = {} }
      local result = runner.build_command(task, ctx)
      assert.same({ "cmake", "--build", "build/debug" }, result)
    end)

    it("uses cmd when build_preset is available", function()
      local task = {
        cmd = { "cmake", "--build", "--preset", "${build_preset}" },
        fallback_cmd = { "cmake", "--build", "${binary_dir}" },
        needs_build_preset = true,
      }
      local ctx = { variables = { build_preset = "debug" }, args = {} }
      local result = runner.build_command(task, ctx)
      assert.same({ "cmake", "--build", "--preset", "debug" }, result)
    end)

    it("appends args when args_passthrough is true", function()
      local task = { cmd = { "run", "${target}" }, args_passthrough = true }
      local ctx = { variables = { target = "app" }, args = { "--verbose", "--debug" } }
      local result = runner.build_command(task, ctx)
      assert.same({ "run", "app", "--verbose", "--debug" }, result)
    end)

    it("does not append args when args_passthrough is false", function()
      local task = { cmd = { "build" } }
      local ctx = { variables = {}, args = { "--extra" } }
      local result = runner.build_command(task, ctx)
      assert.same({ "build" }, result)
    end)
  end)

  describe("is_cmake_configured", function()
    it("returns false when binary_dir is nil", function()
      assert.is_false(runner.is_cmake_configured("/project", nil))
    end)

    it("returns false when binary_dir is empty", function()
      assert.is_false(runner.is_cmake_configured("/project", ""))
    end)

    it("returns false when CMakeCache.txt does not exist", function()
      assert.is_false(runner.is_cmake_configured("/nonexistent", "build"))
    end)

    it("returns true when CMakeCache.txt exists", function()
      -- Use the test fixture which has a CMakeCache.txt
      local fixture_root = vim.fn.getcwd() .. "/tests/fixtures/cmake-presets"
      assert.is_true(runner.is_cmake_configured(fixture_root, "build"))
    end)
  end)
end)
