"""Pytest fixtures for project-tasks tests."""

import os
import shutil
import tempfile
from pathlib import Path

import pytest

from .nvim_driver import NvimTestDriver, copy_fixture


@pytest.fixture
def plugin_root() -> Path:
    """Get plugin root directory."""
    return Path(__file__).parent.parent.parent


@pytest.fixture
def fixtures_dir(plugin_root) -> Path:
    """Get fixtures directory."""
    return plugin_root / "tests" / "fixtures"


@pytest.fixture
def temp_dir():
    """Create a temporary directory that's cleaned up after test."""
    path = tempfile.mkdtemp(prefix="project_tasks_test_")
    yield path
    if os.path.exists(path):
        shutil.rmtree(path)


@pytest.fixture
def cmake_presets_workspace(temp_dir):
    """Copy cmake-presets fixture to temp dir."""
    return copy_fixture("cmake-presets", temp_dir)


@pytest.fixture
def cmake_no_presets_workspace(temp_dir):
    """Copy cmake-no-presets fixture to temp dir."""
    return copy_fixture("cmake-no-presets", temp_dir)


@pytest.fixture
def python_uv_workspace(temp_dir):
    """Copy python-uv fixture to temp dir."""
    return copy_fixture("python-uv", temp_dir)


@pytest.fixture
def nvim():
    """Create a headless nvim instance with temp workspace."""
    driver = NvimTestDriver()
    yield driver
    driver.close()


@pytest.fixture
def nvim_cmake_presets(cmake_presets_workspace):
    """Create nvim instance in cmake-presets workspace."""
    driver = NvimTestDriver(workspace_path=cmake_presets_workspace)
    yield driver
    driver.close()


@pytest.fixture
def nvim_cmake_no_presets(cmake_no_presets_workspace):
    """Create nvim instance in cmake-no-presets workspace."""
    driver = NvimTestDriver(workspace_path=cmake_no_presets_workspace)
    yield driver
    driver.close()


@pytest.fixture
def nvim_python_uv(python_uv_workspace):
    """Create nvim instance in python-uv workspace."""
    driver = NvimTestDriver(workspace_path=python_uv_workspace)
    yield driver
    driver.close()
