-- Unit tests for project-tasks/init.lua helpers
local helpers = require("helpers")
local pt = require("project-tasks")

describe("init helpers", function()
	describe("get_target_arg_from_build_preset", function()
		it("builds --target args from build preset targets", function()
			local arg = pt.get_target_arg_from_build_preset({ targets = { "app", "tests" } })
			assert.equals("--target app --target tests", arg)
		end)

		it("returns nil when targets are missing", function()
			assert.is_nil(pt.get_target_arg_from_build_preset({}))
			assert.is_nil(pt.get_target_arg_from_build_preset({ targets = {} }))
		end)
	end)

	describe("build target scope/signature", function()
		it("scopes by build preset and configure preset", function()
			local ctx = {
				variables = {
					build_preset = "debug",
					preset = "debug",
					binary_dir = "build/debug",
				},
			}
			local scope = pt.get_build_target_scope(ctx)
			assert.equals("build_preset:debug|preset:debug", scope)
		end)

		it("signature changes when binary_dir changes", function()
			local ctx_a = {
				variables = {
					build_preset = "debug",
					preset = "debug",
					binary_dir = "build/debug",
				},
			}
			local ctx_b = {
				variables = {
					build_preset = "debug",
					preset = "debug",
					binary_dir = "build/release",
				},
			}

			assert.not_equals(pt.get_build_target_signature(ctx_a), pt.get_build_target_signature(ctx_b))
		end)
	end)

	describe("apply_configure_preset_context", function()
		it("maps configure preset to binary_dir", function()
			local root = helpers.fixture_path("cmake-presets")
			local ctx = {
				root = root,
				variables = {
					build_dir = "build",
				},
			}

			pt.apply_configure_preset_context(ctx, "debug")

			assert.equals("debug", ctx.variables.preset)
			assert.equals("debug", ctx.variables.configure_preset)
			assert.equals(root .. "/build/debug", ctx.variables.binary_dir)
		end)
	end)
end)
