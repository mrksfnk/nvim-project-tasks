"""Simple test to verify pytest works."""

from src.main import main


def test_hello():
    """Test that main returns 0."""
    assert main() == 0


def test_main_output(capsys):
    """Test that main prints expected output."""
    main()
    captured = capsys.readouterr()
    assert "Hello from test-python-app!" in captured.out
