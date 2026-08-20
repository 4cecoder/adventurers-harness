"""
Hindsight Local Memory Server (Docker Container)
Lightweight on-device episodic and semantic memory store with health check endpoints.
"""

from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import os
import sys

PORT = int(os.environ.get("PORT", 8888))

# In-memory storage for memory documents & initiatives
KNOWLEDGE_STORE = {}

class HindsightHTTPHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ("/health", "/api/v1/health"):
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"status": "healthy", "service": "hindsight-local", "engine": "docker"}).encode())
        elif self.path.startswith("/api/v1/knowledge"):
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"pages": list(KNOWLEDGE_STORE.values())}).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path.startswith("/api/v1/knowledge/ingest"):
            length = int(self.headers.get("Content-Length", 0))
            data = json.loads(self.rfile.read(length).decode()) if length > 0 else {}
            title = data.get("title", "Untitled")
            KNOWLEDGE_STORE[title] = data
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"success": True, "stored_title": title, "count": len(KNOWLEDGE_STORE)}).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        sys.stderr.write(f"[Hindsight-Docker] {format % args}\n")

def run():
    server = HTTPServer(("0.0.0.0", PORT), HindsightHTTPHandler)
    print(f"Hindsight Local Server listening on port {PORT}...")
    server.serve_forever()

if __name__ == "__main__":
    run()
