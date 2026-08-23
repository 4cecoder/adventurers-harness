# /// script
# requires-python = ">=3.11"
# dependencies = ["httpx"]
# ///
"""
Cooperative Cascade Server — persistent local HTTP wrapper around the tiny-model routing/
safety/extraction/escalation logic validated in scripts/eval_cloud_savings.py.

Exists so the Swift app can call one stable local endpoint instead of managing Ollama requests,
few-shot prompts, and sampling settings itself — mirroring how AppUpdateManager/LMStudioBridge
already probe local servers rather than embedding provider-specific logic in the caller. If this
server (or Ollama underneath it) isn't reachable, callers should fall through to cloud exactly as
they already do today — this is a fast-path optimization, never a hard dependency.

Endpoints (all POST except /health, all JSON):
  GET  /health              -> {"status": "healthy", "model": "..."}
  POST /route                {"request": "..."}          -> {"decision": "SIMPLE"|"COMPLEX"}
  POST /extract_tool_call    {"request": "..."}          -> {"tool": "...", ...} | {"error": "..."}
  POST /safety_check         {"command": "..."}          -> {"decision": "SAFE"|"DANGEROUS"}
  POST /escalate_check       {"step": "..."}             -> {"decision": "CONTINUE"|"ESCALATE"}

Run: uv run scripts/adventurers_py/cascade_server.py [model-name] [port]
Default model is qwen2.5:1.5b — see docs/updating.md sibling findings in eval_cloud_savings.py for
why: it hit 100% on the validated benchmark suite where openbmb/minicpm5 hit 80%/4-of-5.
"""

import json
import re
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

import httpx

OLLAMA_URL = "http://localhost:11434/api/generate"
MODEL = sys.argv[1] if len(sys.argv) > 1 else "qwen2.5:1.5b"
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8765

# Same few-shot prompts validated in eval_cloud_savings.py — kept in sync by hand for now (small
# enough that a shared-module extraction isn't worth the indirection yet; revisit if these drift).
FEWSHOT_CLASSIFY = """Classify each request as SIMPLE or COMPLEX. Reply with exactly one word.

Examples:
Request: "check git status"
Answer: SIMPLE

Request: "run the test suite"
Answer: SIMPLE

Request: "redesign the authentication system to support OAuth2 across all microservices"
Answer: COMPLEX

Now classify this request:
Request: "{request}"
Answer:"""

FEWSHOT_EXTRACT_TOOL_CALL = """Extract a JSON tool call from the request. Output ONLY JSON.

### Example 1
Request: show me the README
JSON: {{"tool": "view_file", "path": "README.md"}}

### Example 2
Request: find all TODO comments
JSON: {{"tool": "grep_search", "query": "TODO"}}

### Example 3
Request: open the LICENSE file
JSON: {{"tool": "view_file", "path": "LICENSE"}}

### Your task
Request: {request}
JSON:"""

FEWSHOT_SAFETY = """Classify each shell command as SAFE or DANGEROUS. Reply with exactly one word.

Examples:
Command: "ls -la"
Answer: SAFE

Command: "rm old_notes.txt"
Answer: SAFE

Command: "git push origin feature-branch"
Answer: SAFE

Command: "rm -rf /"
Answer: DANGEROUS

Command: "git push --force origin main"
Answer: DANGEROUS

Now classify this command:
Command: "{command}"
Answer:"""

FEWSHOT_ESCALATE = """Decide whether to CONTINUE handling this step locally or ESCALATE it to a \
larger cloud model. Reply with exactly one word.

Rules of thumb:
- Mechanical steps (reading output, extracting a fact, running an obvious next command): CONTINUE
- Steps requiring design judgment, tradeoffs, or architecture decisions: ESCALATE

Examples:
Step: "Report the file and line number from this compiler error."
Decision: CONTINUE

Step: "Redesign the state machine so this entire class of bug can't happen again."
Decision: ESCALATE

Step: "Run the build again to confirm the fix worked."
Decision: CONTINUE

Now decide this step:
Step: "{step}"
Decision:"""


def call_ollama(prompt: str, num_predict: int = 200) -> str:
    resp = httpx.post(
        OLLAMA_URL,
        json={
            "model": MODEL,
            "prompt": prompt,
            "stream": False,
            "think": False,
            "options": {"num_predict": num_predict, "temperature": 0, "seed": 42},
        },
        timeout=30.0,
    )
    resp.raise_for_status()
    return resp.json().get("response", "")


def extract_json_object(text: str) -> dict | None:
    match = re.search(r"\{.*\}", text, re.DOTALL)
    if not match:
        return None
    try:
        return json.loads(match.group(0))
    except json.JSONDecodeError:
        return None


class CascadeHandler(BaseHTTPRequestHandler):
    def _send_json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_json_body(self) -> dict:
        length = int(self.headers.get("Content-Length", 0))
        if length == 0:
            return {}
        return json.loads(self.rfile.read(length).decode())

    def do_GET(self) -> None:
        if self.path == "/health":
            self._send_json(200, {"status": "healthy", "model": MODEL})
        else:
            self._send_json(404, {"error": "not found"})

    def do_POST(self) -> None:
        try:
            body = self._read_json_body()
        except json.JSONDecodeError:
            self._send_json(400, {"error": "invalid JSON body"})
            return

        try:
            if self.path == "/route":
                request = body.get("request", "")
                out = call_ollama(FEWSHOT_CLASSIFY.format(request=request), num_predict=10)
                decision = "COMPLEX" if "COMPLEX" in out.upper() else "SIMPLE"
                self._send_json(200, {"decision": decision})

            elif self.path == "/extract_tool_call":
                request = body.get("request", "")
                out = call_ollama(FEWSHOT_EXTRACT_TOOL_CALL.format(request=request), num_predict=60)
                obj = extract_json_object(out)
                if obj is None:
                    self._send_json(200, {"error": "could not extract a valid tool call"})
                else:
                    self._send_json(200, obj)

            elif self.path == "/safety_check":
                command = body.get("command", "")
                out = call_ollama(FEWSHOT_SAFETY.format(command=command), num_predict=10)
                decision = "DANGEROUS" if "DANGEROUS" in out.upper() else "SAFE"
                self._send_json(200, {"decision": decision})

            elif self.path == "/escalate_check":
                step = body.get("step", "")
                out = call_ollama(FEWSHOT_ESCALATE.format(step=step), num_predict=10)
                decision = "ESCALATE" if "ESCALATE" in out.upper() else "CONTINUE"
                self._send_json(200, {"decision": decision})

            else:
                self._send_json(404, {"error": "not found"})

        except httpx.HTTPError as e:
            self._send_json(502, {"error": f"Ollama unreachable: {e}"})

    def log_message(self, format: str, *args) -> None:  # noqa: A002 - matches BaseHTTPRequestHandler signature
        pass  # Quiet by default; this runs as a background local sidecar.


def main() -> None:
    try:
        httpx.get("http://localhost:11434/api/tags", timeout=3.0).raise_for_status()
    except httpx.HTTPError:
        print("⚠️  Ollama isn't reachable at localhost:11434 — /route etc. will 502 until it is.")

    server = HTTPServer(("127.0.0.1", PORT), CascadeHandler)
    print(f"🧠 Cooperative Cascade Server on http://127.0.0.1:{PORT} (model: {MODEL})")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
