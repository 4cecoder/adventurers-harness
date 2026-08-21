"""
Adventurers Docker & Local Compose Service Manager
Auto-connects to local Docker Compose containers (Hindsight memory & sandbox runner)
with automatic fallback to native on-device OKF Knowledge Packets when Docker is offline.
"""

import subprocess
import shutil
import socket
import httpx
import os
from typing import Dict, Any

HINDSIGHT_PORT = 8888
COMPOSE_FILE = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "docker-compose.yml",
)


def is_docker_installed() -> bool:
    """Checks if the docker CLI is present in PATH."""
    return shutil.which("docker") is not None


def is_docker_daemon_running(timeout_sec: float = 1.0) -> bool:
    """Checks if the Docker daemon is responding."""
    if not is_docker_installed():
        return False
    try:
        res = subprocess.run(
            ["docker", "info", "--format", "{{.ServerVersion}}"],
            capture_output=True,
            text=True,
            timeout=timeout_sec,
        )
        return res.returncode == 0
    except Exception:
        return False


def is_port_listening(port: int, host: str = "127.0.0.1", timeout_sec: float = 0.2) -> bool:
    """Checks if a TCP port is active on host."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(timeout_sec)
            s.connect((host, port))
        return True
    except Exception:
        return False


def check_hindsight_health(port: int = HINDSIGHT_PORT) -> Dict[str, Any]:
    """Probes the local Hindsight Docker container health endpoint."""
    if not is_port_listening(port):
        return {"running": False, "status": "offline", "port": port}
    try:
        with httpx.Client(timeout=1.0) as client:
            resp = client.get(f"http://127.0.0.1:{port}/health")
            if resp.status_code == 200:
                data = resp.json()
                return {
                    "running": True,
                    "status": data.get("status", "healthy"),
                    "service": data.get("service", "hindsight-local"),
                }
    except Exception as e:
        return {"running": False, "status": f"error: {str(e)}", "port": port}
    return {"running": False, "status": "offline", "port": port}


def start_docker_compose(compose_file: str = COMPOSE_FILE) -> Dict[str, Any]:
    """Starts local Docker Compose services in detached mode with build."""
    if not is_docker_daemon_running():
        return {
            "success": False,
            "error": "Docker daemon is not running. Please launch Docker Desktop or colima.",
        }

    try:
        cmd = ["docker", "compose", "-f", compose_file, "up", "-d", "--build"]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=180.0)
        return {"success": res.returncode == 0, "output": res.stdout or res.stderr}
    except Exception as e:
        return {"success": False, "error": str(e)}


def stop_docker_compose(compose_file: str = COMPOSE_FILE) -> Dict[str, Any]:
    """Stops local Docker Compose services."""
    if not is_docker_daemon_running():
        return {"success": False, "error": "Docker daemon is not running."}

    try:
        cmd = ["docker", "compose", "-f", compose_file, "down"]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=20.0)
        return {"success": res.returncode == 0, "output": res.stdout or res.stderr}
    except Exception as e:
        return {"success": False, "error": str(e)}


def get_docker_status_summary() -> Dict[str, Any]:
    """Returns a full health and connectivity report for Docker & Hindsight."""
    installed = is_docker_installed()
    daemon_running = is_docker_daemon_running() if installed else False
    hindsight_info = check_hindsight_health()

    return {
        "docker_installed": installed,
        "daemon_running": daemon_running,
        "hindsight_container": hindsight_info,
        "active_memory_mode": "docker_hindsight"
        if hindsight_info["running"]
        else "native_on_device_okf",
    }
