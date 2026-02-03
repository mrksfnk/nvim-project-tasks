-- Unit tests for project-tasks/presets.lua
local helpers = require("helpers")
local presets = require("project-tasks.presets")

describe("presets", function()
  describe("load", function()
    it("loads presets from CMakePresets.json", function()
      local fixture = helpers.fixture_path("cmake-presets")
      local result = presets.load(fixture)

      assert.is_not_nil(result)
      assert.is_true(#result >= 2) -- debug and release

      local names = {}
      for _, p in ipairs(result) do
        names[p.name] = true
      end
      assert.is_true(names["debug"])
      assert.is_true(names["release"])
    end)

    it("filters hidden presets", function()
      local fixture = helpers.fixture_path("cmake-presets")
      local result = presets.load(fixture)

      for _, p in ipairs(result) do
        assert.is_not_equal("base", p.name)
      end
    end)

    it("resolves inheritance", function()
      local fixture = helpers.fixture_path("cmake-presets")
      local result = presets.load(fixture)

      local debug_preset = nil
      for _, p in ipairs(result) do
        if p.name == "debug" then
          debug_preset = p
          break
        end
      end

      assert.is_not_nil(debug_preset)
      -- Should inherit binaryDir from base
      assert.is_not_nil(debug_preset.binaryDir)
      assert.matches("build", debug_preset.binaryDir)
    end)

    it("expands macros in binaryDir", function()
      local fixture = helpers.fixture_path("cmake-presets")
      local result = presets.load(fixture)

      local debug_preset = nil
      for _, p in ipairs(result) do
        if p.name == "debug" then
          debug_preset = p
          break
        end
      end

      -- binaryDir should be ${sourceDir}/build/${presetName} expanded
      -- Which is: <fixture>/build/debug
      local expected_binary_dir = fixture .. "/build/debug"
      assert.equals(expected_binary_dir, debug_preset.binaryDir)
    end)

    it("provides default binaryDir when preset lacks one", function()
      -- Presets without binaryDir should get a default of build/<presetName>
      local fixture = helpers.fixture_path("cmake-no-binarydir")
      local result = presets.load(fixture)

      assert.is_not_nil(result)
      for _, p in ipairs(result) do
        -- All presets should have binaryDir (either defined or default)
        assert.is_not_nil(p.binaryDir, "preset " .. p.name .. " should have binaryDir")
        -- Default should be build/<presetName>
        assert.matches("build/" .. p.name, p.binaryDir)
      end
    end)

    it("returns nil for project without presets", function()
      local fixture = helpers.fixture_path("cmake-no-presets")
      local result = presets.load(fixture)
      assert.is_nil(result)
    end)

    it("returns nil for non-cmake project", function()
      local fixture = helpers.fixture_path("python-uv")
      local result = presets.load(fixture)
      assert.is_nil(result)
    end)
  end)

  describe("expand_macros", function()
    it("expands ${sourceDir}", function()
      local result = presets.expand_macros("${sourceDir}/build", { sourceDir = "/home/user/project" })
      assert.equals("/home/user/project/build", result)
    end)

    it("expands ${presetName}", function()
      local result = presets.expand_macros("build/${presetName}", { presetName = "debug" })
      assert.equals("build/debug", result)
    end)

    it("expands multiple macros", function()
      local result = presets.expand_macros("${sourceDir}/build/${presetName}", {
        sourceDir = "/project",
        presetName = "release",
      })
      assert.equals("/project/build/release", result)
    end)

    it("preserves unknown macros", function()
      local result = presets.expand_macros("${unknown}/path", {})
      assert.equals("${unknown}/path", result)
    end)
  end)

  describe("read_presets_file", function()
    it("returns parsed JSON for valid file", function()
      local fixture = helpers.fixture_path("cmake-presets")
      local result = presets.read_presets_file(fixture .. "/CMakePresets.json")
      assert.is_not_nil(result)
      assert.is_not_nil(result.configurePresets)
    end)

    it("returns nil for non-existent file", function()
      local result = presets.read_presets_file("/nonexistent/file.json")
      assert.is_nil(result)
    end)
  end)

  describe("get_targets", function()
    it("returns nil when binary_dir is nil", function()
      local result = presets.get_targets("/some/root", nil)
      assert.is_nil(result)
    end)

    it("returns nil when build dir has no cmake api reply", function()
      -- Use a temp directory that exists but has no .cmake/api/v1/reply
      local fixture = helpers.fixture_path("cmake-no-presets")
      local result = presets.get_targets(fixture, fixture .. "/build")
      assert.is_nil(result)
    end)
  end)

  describe("has_build_preset", function()
    it("returns true when build presets exist", function()
      local fixture = helpers.fixture_path("cmake-presets")
      -- Load first to populate cache
      presets.load(fixture)
      local result = presets.has_build_preset(fixture)
      assert.is_true(result)
    end)

    it("returns false when no build presets exist", function()
      local fixture = helpers.fixture_path("cmake-configure-presets-only")
      -- Load first to populate cache
      presets.load(fixture)
      local result = presets.has_build_preset(fixture)
      assert.is_false(result)
    end)

    it("returns false for non-cmake project", function()
      local fixture = helpers.fixture_path("python-uv")
      local result = presets.has_build_preset(fixture)
      assert.is_false(result)
    end)
  end)

  describe("get_build_presets", function()
    it("returns build presets when they exist", function()
      local fixture = helpers.fixture_path("cmake-presets")
      presets.load(fixture)
      local result = presets.get_build_presets(fixture)
      assert.is_not_nil(result)
      assert.is_true(#result >= 1)
    end)

    it("returns empty table when no build presets", function()
      local fixture = helpers.fixture_path("cmake-configure-presets-only")
      presets.load(fixture)
      local result = presets.get_build_presets(fixture)
      assert.same({}, result)
    end)
  end)
end)
