"""Neovim test driver for headless testing via RPC."""

import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Any, Optional

import pynvim


class NvimTestDriver:
    """Driver for controlling headless Neovim instance."""

    def __init__(
        self,
        workspace_path: Optional[str] = None,
        timeout: float = 30.0,
        init_lua: Optional[str] = None,
    ):
        """Initialize headless Neovim.

        Args:
            workspace_path: Working directory for nvim. Defaults to temp dir.
            timeout: Default timeout for operations in seconds.
            init_lua: Path to init.lua. Defaults to tests/minimal_init.lua.
        """
        self.timeout = timeout
        self.workspace = workspace_path or tempfile.mkdtemp(prefix="nvim_test_")
        self._owns_workspace = workspace_path is None

        # Find plugin root (parent of tests/)
        self.plugin_root = Path(__file__).parent.parent.parent
        self.init_lua = init_lua or str(self.plugin_root / "tests" / "minimal_init.lua")

        # Socket for RPC
        self.socket = tempfile.mktemp(suffix=".sock")

        # Start headless nvim - run from plugin root so runtimepath works
        self.proc = subprocess.Popen(
            [
                "nvim",
                "--headless",
                "--listen",
                self.socket,
                "-u",
                self.init_lua,
            ],
            cwd=str(self.plugin_root),  # Run from plugin root!
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

        # Wait for socket and connect
        self._wait_for_socket()
        self.nvim = pynvim.attach("socket", path=self.socket)

        # Change to workspace
        self.nvim.command(f"cd {self.workspace}")

        # Configure plugin to use terminal mode for integration tests
        self.lua("""
            require('project-tasks').setup({
                terminal = { mode = 'terminal' }
            })
        """)

    def _wait_for_socket(self, timeout: float = 5.0):
        """Wait for nvim socket to be available."""
        start = time.time()
        while time.time() - start < timeout:
            if os.path.exists(self.socket):
                # Give nvim a moment to fully initialize
                time.sleep(0.1)
                return
            time.sleep(0.05)
        raise TimeoutError(f"Neovim socket not created within {timeout}s")

    def command(self, cmd: str) -> None:
        """Execute a Vim command."""
        self.nvim.command(cmd)

    def eval(self, expr: str) -> Any:
        """Evaluate a Vim expression."""
        return self.nvim.eval(expr)

    def lua(self, code: str) -> Any:
        """Execute Lua code and return result."""
        return self.nvim.exec_lua(code)

    def call_function(self, name: str, *args) -> Any:
        """Call a Vim function."""
        return self.nvim.call(name, *args)

    def run_task(self, task_name: str, prompt: bool = False) -> None:
        """Run a project task.

        Args:
            task_name: Task name (configure, build, run, etc.)
            prompt: Whether to force target/preset selection.
        """
        cmd_name = f"Project{task_name.capitalize()}"
        if prompt:
            self.command(f"{cmd_name}!")
        else:
            self.command(cmd_name)

    def run_task_lua(
        self,
        task_name: str,
        prompt: bool = False,
        args: Optional[list] = None,
        env: Optional[dict] = None,
    ) -> None:
        """Run a project task via Lua API.

        Args:
            task_name: Task name.
            prompt: Force selection prompt.
            args: Arguments to pass to task.
            env: Environment variables.
        """
        opts = {"prompt": prompt}
        if args:
            opts["args"] = args
        if env:
            opts["env"] = env

        self.lua(
            f"""
            require('project-tasks').run_task('{task_name}', vim.json.decode('{__import__("json").dumps(opts)}'))
        """
        )

    def get_terminal_buffers(self) -> list[int]:
        """Get list of terminal buffer numbers."""
        buffers = []
        for buf in self.nvim.buffers:
            buftype = self.nvim.call("getbufvar", buf.number, "&buftype")
            if buftype == "terminal":
                buffers.append(buf.number)
        return buffers

    def get_terminal_content(self, buf_nr: Optional[int] = None) -> str:
        """Get content of terminal buffer.

        Args:
            buf_nr: Buffer number. If None, uses first terminal buffer.

        Returns:
            Terminal content as string.
        """
        if buf_nr is None:
            terminals = self.get_terminal_buffers()
            if not terminals:
                return ""
            buf_nr = terminals[0]

        lines = self.nvim.call("getbufline", buf_nr, 1, "$")
        return "\n".join(lines)

    def wait_for_terminal_content(
        self,
        pattern: str,
        timeout: Optional[float] = None,
        buf_nr: Optional[int] = None,
    ) -> bool:
        """Wait for terminal to contain pattern.

        Args:
            pattern: String to search for.
            timeout: Max wait time in seconds.
            buf_nr: Terminal buffer number.

        Returns:
            True if pattern found, False if timeout.
        """
        timeout = timeout or self.timeout
        start = time.time()

        while time.time() - start < timeout:
            content = self.get_terminal_content(buf_nr)
            if pattern in content:
                return True
            time.sleep(0.1)

        return False

    def wait_for_job_complete(
        self,
        timeout: Optional[float] = None,
        buf_nr: Optional[int] = None,
    ) -> bool:
        """Wait for terminal job to complete.

        Args:
            timeout: Max wait time in seconds.
            buf_nr: Terminal buffer number.

        Returns:
            True if job completed, False if timeout.
        """
        timeout = timeout or self.timeout

        if buf_nr is None:
            terminals = self.get_terminal_buffers()
            if not terminals:
                return True  # No terminal = nothing to wait for
            buf_nr = terminals[0]

        start = time.time()
        while time.time() - start < timeout:
            job_id = self.nvim.call("getbufvar", buf_nr, "terminal_job_id")
            if job_id:
                status = self.nvim.call("jobwait", [job_id], 100)
                if status[0] != -1:
                    return True
            time.sleep(0.1)

        return False

    def get_last_notification(self) -> Optional[str]:
        """Get the last vim.notify message (if captured)."""
        return self.lua("return vim.g.project_tasks_last_notification")

    def get_detected_backend(self) -> Optional[str]:
        """Get the detected backend for current workspace."""
        return self.lua(
            """
            local detect = require('project-tasks.detect')
            local pt = require('project-tasks')
            local root = detect.find_root()
            if not root then return nil end
            local name, _ = detect.get_backend(root, pt.config.backends)
            return name
        """
        )

    def get_available_tasks(self) -> list[str]:
        """Get list of available tasks for current backend."""
        result = self.lua(
            """
            local detect = require('project-tasks.detect')
            local pt = require('project-tasks')
            local root = detect.find_root()
            if not root then return {} end
            local _, backend = detect.get_backend(root, pt.config.backends)
            if not backend or not backend.tasks then return {} end
            return vim.tbl_keys(backend.tasks)
        """
        )
        return result or []

    def set_preset(self, preset_name: str) -> None:
        """Set the preset in session for current workspace."""
        self.lua(
            f"""
            local detect = require('project-tasks.detect')
            local session = require('project-tasks.session')
            local root = detect.find_root()
            if root then
                session.set(root, 'preset', '{preset_name}')
            end
        """
        )

    def set_build_preset(self, preset_name: str) -> None:
        """Set the build preset in session for current workspace."""
        self.lua(
            f"""
            local detect = require('project-tasks.detect')
            local session = require('project-tasks.session')
            local root = detect.find_root()
            if root then
                session.set(root, 'build_preset', '{preset_name}')
            end
        """
        )

    def set_build_target(self, target_name: str) -> None:
        """Set the build target in session for current workspace.

        Args:
            target_name: Target name, or empty string for 'all'.
        """
        self.lua(
            f"""
            local detect = require('project-tasks.detect')
            local session = require('project-tasks.session')
            local root = detect.find_root()
            if root then
                session.set(root, 'build_target', '{target_name}')
            end
        """
        )

    def set_target(self, target_name: str) -> None:
        """Set the target in session for current workspace."""
        self.lua(
            f"""
            local detect = require('project-tasks.detect')
            local session = require('project-tasks.session')
            local root = detect.find_root()
            if root then
                session.set(root, 'target', '{target_name}')
            end
        """
        )

    def cancel_task(self) -> None:
        """Cancel the currently running task."""
        self.lua("require('project-tasks').run_task('cancel')")

    def get_quickfix_content(self) -> str:
        """Get content of the quickfix list."""
        items = self.nvim.call("getqflist")
        return "\n".join(item.get("text", "") for item in items)

    def wait_for_quickfix_content(
        self,
        pattern: str,
        timeout: Optional[float] = None,
    ) -> bool:
        """Wait for quickfix list to contain pattern.

        Args:
            pattern: String to search for.
            timeout: Max wait time in seconds.

        Returns:
            True if pattern found, False if timeout.
        """
        timeout = timeout or self.timeout
        start = time.time()

        while time.time() - start < timeout:
            content = self.get_quickfix_content()
            if pattern in content:
                return True
            time.sleep(0.1)

        return False

    def is_task_running(self) -> bool:
        """Check if a task is currently running."""
        return self.lua(
            """
            local runner = require('project-tasks.runner')
            return runner.current_job ~= nil
        """
        )

    def close(self) -> None:
        """Shutdown nvim and cleanup."""
        try:
            self.nvim.command("qa!")
        except Exception:
            pass

        try:
            self.nvim.close()
        except Exception:
            pass

        try:
            self.proc.terminate()
            self.proc.wait(timeout=2)
        except Exception:
            self.proc.kill()

        # Cleanup socket
        if os.path.exists(self.socket):
            os.unlink(self.socket)

        # Cleanup workspace if we created it
        if self._owns_workspace and os.path.exists(self.workspace):
            shutil.rmtree(self.workspace)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()
        return False


def copy_fixture(fixture_name: str, dest: Optional[str] = None) -> str:
    """Copy a fixture to a temporary directory.

    Args:
        fixture_name: Name of fixture directory (e.g., 'cmake-presets').
        dest: Destination path. If None, creates temp dir.

    Returns:
        Path to copied fixture.
    """
    tests_dir = Path(__file__).parent.parent
    fixture_src = tests_dir / "fixtures" / fixture_name

    if not fixture_src.exists():
        raise FileNotFoundError(f"Fixture not found: {fixture_src}")

    if dest is None:
        dest = tempfile.mkdtemp(prefix=f"fixture_{fixture_name}_")

    shutil.copytree(fixture_src, dest, dirs_exist_ok=True)
    return dest
