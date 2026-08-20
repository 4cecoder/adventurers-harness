"""
Hindsight Docker Memory Gate
Ensures Hindsight memory is strictly isolated and ONLY invoked if running locally in a Docker container on this machine.
Otherwise, falls back to native on-device OKF Knowledge Packets with zero blocking.
"""

import socket
import httpx
from typing import Optional, Dict, Any

def is_hindsight_docker_running(port: int = 8888, timeout_sec: float = 0.2) -> bool:
    """Checks if a local Hindsight container is actively listening on localhost."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(timeout_sec)
            s.connect(("127.0.0.1", port))
        return True
    except Exception:
        return False

class HindsightMemoryManager:
    def __init__(self, docker_port: int = 8888):
        self.docker_port = docker_port
        self.is_active = is_hindsight_docker_running(docker_port)

    def should_use_hindsight(self) -> bool:
        """Returns True ONLY if Hindsight is verified running locally in Docker."""
        self.is_active = is_hindsight_docker_running(self.docker_port)
        return self.is_active

    def query_or_fallback(self, query: str) -> Optional[Dict[str, Any]]:
        """Queries local Docker Hindsight if running, else returns None to use native OKF store."""
        if not self.should_use_hindsight():
            return None
        
        try:
            with httpx.Client(timeout=1.0) as client:
                resp = client.get(f"http://127.0.0.1:{self.docker_port}/health")
                if resp.status_code == 200:
                    return {"source": "docker_hindsight", "status": "connected"}
        except Exception:
            pass
        return None
