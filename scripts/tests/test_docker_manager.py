"""
Unit tests for Docker Manager and Docker Compose connectivity.
"""

import pytest
from adventurers_py.docker_manager import (
    is_docker_installed,
    is_docker_daemon_running,
    is_port_listening,
    check_hindsight_health,
    get_docker_status_summary
)

def test_docker_installed_check():
    # Should detect docker CLI if installed
    res = is_docker_installed()
    assert isinstance(res, bool)

def test_docker_daemon_offline_safety():
    # Non-blocking probe should return bool without throwing exceptions
    res = is_docker_daemon_running(timeout_sec=0.1)
    assert isinstance(res, bool)

def test_port_listener_probe():
    # Random high port should return False safely
    assert is_port_listening(59998, timeout_sec=0.05) is False

def test_hindsight_health_probe():
    health = check_hindsight_health(port=59998)
    assert health["running"] is False
    assert health["status"] == "offline"

def test_docker_status_summary():
    summary = get_docker_status_summary()
    assert "docker_installed" in summary
    assert "daemon_running" in summary
    assert "hindsight_container" in summary
    assert summary["active_memory_mode"] in ("docker_hindsight", "native_on_device_okf")
