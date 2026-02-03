-- Unit tests for project-tasks/session.lua
local helpers = require("helpers")
local session = require("project-tasks.session")

describe("session", function()
  local original_file_path

  before_each(function()
    -- Use a temp file for session storage
    original_file_path = session.file_path
    session.file_path = vim.fn.tempname() .. ".json"
    session.data = nil -- Clear cache
  end)

  after_each(function()
    -- Cleanup
    if session.file_path and vim.fn.filereadable(session.file_path) == 1 then
      vim.fn.delete(session.file_path)
    end
    session.file_path = original_file_path
    session.data = nil
  end)

  describe("get/set", function()
    it("returns nil for unset key", function()
      local value = session.get("/project/path", "target")
      assert.is_nil(value)
    end)

    it("stores and retrieves values", function()
      session.set("/project/path", "target", "my_app")
      local value = session.get("/project/path", "target")
      assert.equals("my_app", value)
    end)

    it("stores multiple keys per project", function()
      session.set("/project", "target", "app")
      session.set("/project", "preset", "debug")

      assert.equals("app", session.get("/project", "target"))
      assert.equals("debug", session.get("/project", "preset"))
    end)

    it("stores data for multiple projects", function()
      session.set("/project1", "target", "app1")
      session.set("/project2", "target", "app2")

      assert.equals("app1", session.get("/project1", "target"))
      assert.equals("app2", session.get("/project2", "target"))
    end)
  end)

  describe("persistence", function()
    it("persists data to file", function()
      session.set("/project", "target", "my_app")

      -- Clear cache and reload
      session.data = nil
      local value = session.get("/project", "target")
      assert.equals("my_app", value)
    end)

    it("handles missing session file", function()
      -- File doesn't exist yet
      session.data = nil
      local value = session.get("/project", "target")
      assert.is_nil(value)
    end)
  end)

  describe("clear", function()
    it("clears data for a project", function()
      session.set("/project", "target", "app")
      session.set("/project", "preset", "debug")

      session.clear("/project")

      assert.is_nil(session.get("/project", "target"))
      assert.is_nil(session.get("/project", "preset"))
    end)

    it("does not affect other projects", function()
      session.set("/project1", "target", "app1")
      session.set("/project2", "target", "app2")

      session.clear("/project1")

      assert.is_nil(session.get("/project1", "target"))
      assert.equals("app2", session.get("/project2", "target"))
    end)
  end)
end)
