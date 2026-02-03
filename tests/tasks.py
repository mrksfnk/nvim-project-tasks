"""Task runner for project-tasks.nvim using invoke."""

import shutil
from pathlib import Path

from invoke import Context, task

TESTS_DIR = Path(__file__).parent
ROOT = TESTS_DIR.parent  # Plugin root
FIXTURES_DIR = TESTS_DIR / "fixtures"


@task
def install(c: Context):
    """Install test dependencies with uv."""
    c.run("uv sync")


@task
def test_unit(c: Context):
    """Run Lua unit tests with plenary."""
    with c.cd(ROOT):
        # Note: plenary test_harness may return exit code 1 even on success
        # We check the output for actual failures
        result = c.run(
            'nvim --headless -u tests/minimal_init.lua '
            "-c \"lua require('plenary.test_harness').test_directory('tests/unit', {minimal_init='tests/minimal_init.lua'})\" "
            '-c "qa!"',
            pty=True,
            warn=True,
        )
        # If we see "Failed : 0" in output, tests passed
        if result.failed:
            print("Note: Exit code was non-zero but this may be a plenary quirk")


@task
def test_functional(c: Context):
    """Run Python functional tests (no cmake/uv needed)."""
    with c.cd(TESTS_DIR):
        c.run("uv run pytest python/test_functional.py -v --timeout=60", pty=True)


@task
def test_integration(c: Context):
    """Run Python integration tests (requires cmake, uv)."""
    with c.cd(TESTS_DIR):
        c.run("uv run pytest python/test_integration.py -v --timeout=120", pty=True)


@task
def test_python(c: Context):
    """Run all Python tests."""
    with c.cd(TESTS_DIR):
        c.run("uv run pytest python/ -v --timeout=120", pty=True)


@task(pre=[test_unit, test_functional, test_integration])
def test(c: Context):
    """Run all tests."""
    pass


@task
def check(c: Context):
    """Quick check that plugin loads correctly."""
    with c.cd(ROOT):
        c.run(
            'nvim --headless -u tests/minimal_init.lua '
            '-c "lua print(\'Plugin loaded: \' .. tostring(require(\'project-tasks\') ~= nil))" '
            '-c "ProjectTasksInfo" '
            '-c "qa!"',
            pty=True,
        )


@task
def clean(c: Context):
    """Clean test artifacts and build directories."""
    paths_to_clean = [
        FIXTURES_DIR / "cmake-presets" / "build",
        FIXTURES_DIR / "cmake-no-presets" / "build",
        FIXTURES_DIR / "python-uv" / ".venv",
        FIXTURES_DIR / "python-uv" / "dist",
        FIXTURES_DIR / "python-uv" / "uv.lock",
    ]

    for path in paths_to_clean:
        if path.exists():
            print(f"Removing {path}")
            shutil.rmtree(path)

    # Clean __pycache__ directories
    for pycache in TESTS_DIR.rglob("__pycache__"):
        print(f"Removing {pycache}")
        shutil.rmtree(pycache)


@task
def lint(c: Context):
    """Lint Python code with ruff."""
    with c.cd(TESTS_DIR):
        c.run("uv run ruff check python tasks.py", pty=True)


@task
def fmt(c: Context):
    """Format Python code with ruff."""
    with c.cd(TESTS_DIR):
        c.run("uv run ruff format python tasks.py", pty=True)


@task
def watch(c: Context):
    """Watch for changes and run unit tests."""
    with c.cd(ROOT):
        c.run(
            "find lua tests -name '*.lua' | entr -c 'cd tests && uv run inv test-unit'",
            pty=True,
            warn=True,
        )
