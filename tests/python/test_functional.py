"""Functional tests for project detection."""

import pytest


class TestBackendDetection:
    """Test backend detection in different workspaces."""

    def test_detects_cmake_backend_with_presets(self, nvim_cmake_presets):
        """Should detect cmake backend when CMakePresets.json exists."""
        backend = nvim_cmake_presets.get_detected_backend()
        assert backend == "cmake"

    def test_detects_cmake_backend_without_presets(self, nvim_cmake_no_presets):
        """Should detect cmake backend when only CMakeLists.txt exists."""
        backend = nvim_cmake_no_presets.get_detected_backend()
        assert backend == "cmake"

    def test_detects_python_backend(self, nvim_python_uv):
        """Should detect python backend when pyproject.toml exists."""
        backend = nvim_python_uv.get_detected_backend()
        assert backend == "python"

    def test_no_backend_in_empty_workspace(self, nvim):
        """Should return None for empty workspace."""
        backend = nvim.get_detected_backend()
        assert backend is None


class TestAvailableTasks:
    """Test available tasks for each backend."""

    def test_cmake_tasks_available(self, nvim_cmake_presets):
        """CMake backend should have expected tasks."""
        tasks = nvim_cmake_presets.get_available_tasks()
        assert "configure" in tasks
        assert "build" in tasks
        assert "run" in tasks
        assert "debug" in tasks
        assert "test" in tasks
        assert "clean" in tasks

    def test_python_tasks_available(self, nvim_python_uv):
        """Python backend should have expected tasks."""
        tasks = nvim_python_uv.get_available_tasks()
        assert "run" in tasks
        assert "test" in tasks
        assert "package" in tasks
        # Python doesn't have configure
        assert "configure" not in tasks


class TestPresetsLoading:
    """Test CMake presets loading."""

    def test_loads_presets(self, nvim_cmake_presets):
        """Should load presets from CMakePresets.json."""
        presets = nvim_cmake_presets.lua(
            """
            local presets = require('project-tasks.presets')
            local detect = require('project-tasks.detect')
            local root = detect.find_root()
            return presets.load(root)
        """
        )
        assert presets is not None
        assert len(presets) >= 2

        names = [p["name"] for p in presets]
        assert "debug" in names
        assert "release" in names
        # Hidden preset should be filtered
        assert "base" not in names

    def test_no_presets_returns_nil(self, nvim_cmake_no_presets):
        """Should return nil when no CMakePresets.json exists."""
        presets = nvim_cmake_no_presets.lua(
            """
            local presets = require('project-tasks.presets')
            local detect = require('project-tasks.detect')
            local root = detect.find_root()
            return presets.load(root)
        """
        )
        assert presets is None


class TestSessionPersistence:
    """Test session storage."""

    def test_stores_and_retrieves_preset(self, nvim_cmake_presets):
        """Should store and retrieve preset selection."""
        nvim_cmake_presets.set_preset("debug")

        preset = nvim_cmake_presets.lua(
            """
            local detect = require('project-tasks.detect')
            local session = require('project-tasks.session')
            local root = detect.find_root()
            return session.get(root, 'preset')
        """
        )
        assert preset == "debug"

    def test_stores_and_retrieves_target(self, nvim_cmake_presets):
        """Should store and retrieve target selection."""
        nvim_cmake_presets.set_target("test_app")

        target = nvim_cmake_presets.lua(
            """
            local detect = require('project-tasks.detect')
            local session = require('project-tasks.session')
            local root = detect.find_root()
            return session.get(root, 'target')
        """
        )
        assert target == "test_app"


class TestCommands:
    """Test that commands are registered."""

    def test_commands_exist(self, nvim_cmake_presets):
        """Project commands should be registered."""
        commands = nvim_cmake_presets.lua(
            """
            local cmds = vim.api.nvim_get_commands({})
            local names = {}
            for name, _ in pairs(cmds) do
                if name:match('^Project') then
                    table.insert(names, name)
                end
            end
            return names
        """
        )

        assert "ProjectConfigure" in commands
        assert "ProjectBuild" in commands
        assert "ProjectRun" in commands
        assert "ProjectDebug" in commands
        assert "ProjectTest" in commands
        assert "ProjectClean" in commands
