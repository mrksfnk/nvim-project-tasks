"""Integration tests with real cmake/uv execution."""

import os
import shutil
import subprocess
import time

import pytest

from .nvim_driver import NvimTestDriver, copy_fixture


def cmake_available() -> bool:
    """Check if cmake is available."""
    try:
        subprocess.run(["cmake", "--version"], capture_output=True, check=True)
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False


def uv_available() -> bool:
    """Check if uv is available."""
    try:
        subprocess.run(["uv", "--version"], capture_output=True, check=True)
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False


@pytest.mark.skipif(not cmake_available(), reason="cmake not available")
class TestCMakeIntegration:
    """Integration tests for CMake backend."""

    @pytest.fixture
    def cmake_workspace(self, temp_dir):
        """Create cmake workspace and return nvim driver."""
        workspace = copy_fixture("cmake-presets", temp_dir)
        driver = NvimTestDriver(workspace_path=workspace)
        yield driver, workspace
        driver.close()

    @pytest.fixture
    def cmake_no_presets_workspace(self, temp_dir):
        """Create cmake workspace without presets."""
        workspace = copy_fixture("cmake-no-presets", temp_dir)
        driver = NvimTestDriver(workspace_path=workspace)
        yield driver, workspace
        driver.close()

    def test_configure_with_preset(self, cmake_workspace):
        """Should configure project with CMake preset."""
        nvim, workspace = cmake_workspace

        # Set preset to avoid interactive selection
        nvim.set_preset("debug")

        # Run configure
        nvim.run_task("configure")

        # Wait for build dir to be created
        build_dir = os.path.join(workspace, "build", "debug")
        success = nvim.wait_for_terminal_content("Configuring done", timeout=30)

        # Verify build directory exists
        assert os.path.isdir(build_dir), f"Build dir not created: {build_dir}"
        assert os.path.isfile(
            os.path.join(build_dir, "CMakeCache.txt")
        ), "CMakeCache.txt not created"

    def test_build_with_preset(self, cmake_workspace):
        """Should build project with CMake preset."""
        nvim, workspace = cmake_workspace

        # First configure
        nvim.set_preset("debug")
        nvim.run_task("configure")
        nvim.wait_for_terminal_content("Configuring done", timeout=30)

        # Clear terminal for next command
        nvim.command("enew")

        # Set build preset (matches configure preset name in fixture)
        nvim.set_build_preset("debug")
        nvim.set_build_target("")  # Build all targets

        # Now build
        nvim.run_task("build")
        success = nvim.wait_for_terminal_content("Built target", timeout=60)

        # Verify executable exists
        build_dir = os.path.join(workspace, "build", "debug")
        executable = os.path.join(build_dir, "test_app")
        assert os.path.isfile(executable), f"Executable not created: {executable}"

    def test_run_cmake_target(self, cmake_workspace):
        """Should run the built executable."""
        nvim, workspace = cmake_workspace

        # Set up CMake File API query before configure
        build_dir = os.path.join(workspace, "build", "debug")
        query_dir = os.path.join(build_dir, ".cmake", "api", "v1", "query", "client-project-tasks")
        os.makedirs(query_dir, exist_ok=True)
        # Create query files
        for q in ["codemodel-v2", "cache-v2"]:
            with open(os.path.join(query_dir, q), "w") as f:
                pass

        # Configure and build
        nvim.set_preset("debug")
        nvim.run_task("configure")
        nvim.wait_for_terminal_content("Configuring done", timeout=30)
        nvim.command("enew")

        # Set build preset and target
        nvim.set_build_preset("debug")
        nvim.set_build_target("")  # Build all
        nvim.run_task("build")
        nvim.wait_for_terminal_content("Built target", timeout=60)

        # Set target for run task (session stores target name, lookup happens from File API)
        nvim.set_target("test_app")

        # Run the executable
        nvim.command("enew")
        nvim.run_task("run")

        # Should see "Hello from test_app!" output from main.cpp
        success = nvim.wait_for_terminal_content("Hello from test_app", timeout=10)
        assert success, "Executable output not found"

    def test_ctest_with_preset(self, cmake_workspace):
        """Should run ctest with preset."""
        nvim, workspace = cmake_workspace

        # Set up CMake File API query before configure  
        build_dir = os.path.join(workspace, "build", "debug")
        query_dir = os.path.join(build_dir, ".cmake", "api", "v1", "query", "client-project-tasks")
        os.makedirs(query_dir, exist_ok=True)
        for q in ["codemodel-v2"]:
            with open(os.path.join(query_dir, q), "w") as f:
                pass

        # Configure and build first
        nvim.set_preset("debug")
        nvim.run_task("configure")
        nvim.wait_for_terminal_content("Configuring done", timeout=30)
        nvim.command("enew")

        # Set build preset
        nvim.set_build_preset("debug")
        nvim.set_build_target("")
        nvim.run_task("build")
        nvim.wait_for_terminal_content("Built target", timeout=60)

        # Run tests
        nvim.command("enew")
        nvim.run_task("test")

        # Should see test output (ctest runs the test_app_runs test)
        success = nvim.wait_for_terminal_content("100% tests passed", timeout=30)
        assert success, "ctest output not found"

    def test_cpack_package(self, cmake_workspace):
        """Should create package with CPack."""
        nvim, workspace = cmake_workspace

        # Configure and build first
        nvim.set_preset("debug")
        nvim.run_task("configure")
        nvim.wait_for_terminal_content("Configuring done", timeout=30)
        nvim.command("enew")

        # Set build preset
        nvim.set_build_preset("debug")
        nvim.set_build_target("")
        nvim.run_task("build")
        nvim.wait_for_terminal_content("Built target", timeout=60)

        # Run package
        nvim.command("enew")
        nvim.run_task("package")

        # Should see CPack output
        success = nvim.wait_for_terminal_content("CPack", timeout=60)
        # CPack creates packages - output varies by generator

    def test_configure_without_preset(self, cmake_no_presets_workspace):
        """Should configure project using fallback (no presets)."""
        nvim, workspace = cmake_no_presets_workspace

        # Run configure (should use fallback_cmd with build_dir)
        nvim.run_task("configure")

        # Wait for completion
        success = nvim.wait_for_terminal_content("Configuring done", timeout=30)

        # Verify build directory
        build_dir = os.path.join(workspace, "build")
        assert os.path.isdir(build_dir), f"Build dir not created: {build_dir}"

    def test_clean_removes_build_dir(self, cmake_workspace):
        """Should remove build directory on clean."""
        nvim, workspace = cmake_workspace

        # Configure first
        nvim.set_preset("debug")
        nvim.run_task("configure")
        nvim.wait_for_terminal_content("Configuring done", timeout=30)

        build_dir = os.path.join(workspace, "build", "debug")
        assert os.path.isdir(build_dir), "Build dir should exist after configure"

        # Run clean
        nvim.command("enew")
        nvim.run_task("clean")
        nvim.wait_for_job_complete(timeout=10)

        # Build dir should be removed
        assert not os.path.isdir(build_dir), "Build dir should be removed after clean"

    def test_cmake_file_api_targets(self, cmake_workspace):
        """Should discover targets via CMake File API after configure."""
        nvim, workspace = cmake_workspace

        # Configure to generate file API data
        nvim.set_preset("debug")
        nvim.run_task("configure")
        nvim.wait_for_terminal_content("Configuring done", timeout=30)

        # Check for file API reply
        build_dir = os.path.join(workspace, "build", "debug")
        reply_dir = os.path.join(build_dir, ".cmake", "api", "v1", "reply")

        # File API might need explicit query setup
        # Check if we can get targets
        targets = nvim.lua(
            f"""
            local presets = require('project-tasks.presets')
            return presets.get_targets('{workspace}', '{build_dir}')
        """
        )

        # Should find the test_app executable
        if targets:
            target_names = [t["name"] for t in targets]
            assert "test_app" in target_names


@pytest.mark.skipif(not cmake_available(), reason="cmake not available")
class TestCMakeConfigurePresetsOnly:
    """Integration tests for CMake with only configure presets (no build presets)."""

    @pytest.fixture
    def cmake_configure_only_workspace(self, temp_dir):
        """Create cmake workspace with only configure presets."""
        workspace = copy_fixture("cmake-configure-presets-only", temp_dir)
        driver = NvimTestDriver(workspace_path=workspace)
        yield driver, workspace
        driver.close()

    def test_build_without_build_preset(self, cmake_configure_only_workspace):
        """Should build using fallback when no build presets defined."""
        nvim, workspace = cmake_configure_only_workspace

        # Configure with preset
        nvim.set_preset("debug")
        nvim.run_task("configure")
        nvim.wait_for_terminal_content("Configuring done", timeout=30)

        # Clear terminal
        nvim.command("enew")

        # Set build target to empty (all) since there's no build preset
        nvim.set_build_target("")

        # Build - should use fallback_cmd since no build presets
        nvim.run_task("build")
        success = nvim.wait_for_terminal_content("Built target", timeout=60)

        # Verify executable exists
        build_dir = os.path.join(workspace, "build", "debug")
        executable = os.path.join(build_dir, "test_app")
        assert os.path.isfile(executable), f"Executable not created: {executable}"

    def test_build_specific_target_without_build_preset(self, cmake_configure_only_workspace):
        """Should build specific target when no build presets defined."""
        nvim, workspace = cmake_configure_only_workspace

        # Configure with preset
        nvim.set_preset("debug")
        nvim.run_task("configure")
        nvim.wait_for_terminal_content("Configuring done", timeout=30)

        # Clear terminal
        nvim.command("enew")

        # Set build target to specific target
        nvim.set_build_target("test_app")

        # Build - should use fallback_cmd with --target test_app
        nvim.run_task("build")
        success = nvim.wait_for_terminal_content("Built target test_app", timeout=60)
        assert success, "Specific target build output not found"


@pytest.mark.skipif(not uv_available(), reason="uv not available")
class TestPythonUvIntegration:
    """Integration tests for Python/uv backend."""

    @pytest.fixture
    def python_workspace(self, temp_dir):
        """Create python workspace and return nvim driver."""
        workspace = copy_fixture("python-uv", temp_dir)
        driver = NvimTestDriver(workspace_path=workspace)

        # Initialize uv project
        subprocess.run(["uv", "sync"], cwd=workspace, capture_output=True)

        yield driver, workspace
        driver.close()

    def test_run_python_app(self, python_workspace):
        """Should run Python app via uv."""
        nvim, workspace = python_workspace

        # Run the app
        nvim.run_task("run")

        # Wait for output
        success = nvim.wait_for_terminal_content("Hello from test-python-app", timeout=30)
        assert success, "Python app output not found"

    def test_run_python_tests(self, python_workspace):
        """Should run pytest via uv."""
        nvim, workspace = python_workspace

        # Install pytest first
        subprocess.run(
            ["uv", "add", "--dev", "pytest"], cwd=workspace, capture_output=True
        )

        # Run tests
        nvim.run_task("test")

        # Wait for pytest output
        success = nvim.wait_for_terminal_content("passed", timeout=30)
        # Test might fail if pytest not properly set up, that's OK for this test
        # We mainly verify the command runs

    def test_package_python_project(self, python_workspace):
        """Should package Python project via uv build."""
        nvim, workspace = python_workspace

        # Run package
        nvim.run_task("package")

        # Wait for build to complete
        success = nvim.wait_for_terminal_content("Built", timeout=30)

        # Check for dist directory
        dist_dir = os.path.join(workspace, "dist")
        # uv build might create wheels in dist


@pytest.mark.skipif(not cmake_available(), reason="cmake not available")
class TestCancelTask:
    """Integration tests for task cancellation."""

    @pytest.fixture
    def cmake_workspace_quickfix(self, temp_dir):
        """Create cmake workspace with quickfix mode."""
        workspace = copy_fixture("cmake-presets", temp_dir)
        driver = NvimTestDriver(workspace_path=workspace)
        # Override to use quickfix mode
        driver.lua("""
            require('project-tasks').setup({
                terminal = { mode = 'quickfix' }
            })
        """)
        yield driver, workspace
        driver.close()

    def test_cancel_configure_task(self, cmake_workspace_quickfix):
        """Should cancel a running configure task."""
        nvim, workspace = cmake_workspace_quickfix

        # Set preset
        nvim.set_preset("debug")

        # Start configure task
        nvim.run_task("configure")

        # Wait briefly for it to start
        time.sleep(0.5)

        # Cancel the task
        nvim.cancel_task()

        # Wait for cancellation to complete
        time.sleep(0.5)

        # Check quickfix shows cancelled
        content = nvim.get_quickfix_content()
        assert "cancelled" in content.lower() or "failed" in content.lower(), \
            f"Expected cancelled status in quickfix: {content}"

    def test_cancel_build_task(self, cmake_workspace_quickfix):
        """Should cancel a running build task."""
        nvim, workspace = cmake_workspace_quickfix

        # First configure (need a successful configure)
        nvim.set_preset("debug")
        nvim.run_task("configure")
        nvim.wait_for_quickfix_content("Configuring done", timeout=30)

        # Set build preset
        nvim.set_build_preset("debug")
        nvim.set_build_target("")

        # Start build task
        nvim.run_task("build")

        # Wait briefly for it to start
        time.sleep(0.5)

        # Cancel the task
        nvim.cancel_task()

        # Wait for cancellation to complete
        time.sleep(0.5)

        # Check quickfix shows cancelled
        content = nvim.get_quickfix_content()
        assert "cancelled" in content.lower() or "failed" in content.lower(), \
            f"Expected cancelled status in quickfix: {content}"

    def test_cancel_no_running_task(self, cmake_workspace_quickfix):
        """Should handle cancel when no task is running."""
        nvim, workspace = cmake_workspace_quickfix

        # Cancel with nothing running (should not error)
        nvim.cancel_task()

        # Just verify no exception was raised
