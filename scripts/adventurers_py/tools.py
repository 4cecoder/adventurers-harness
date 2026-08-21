"""
Adventurers Python Core Tools Library
Enterprise tool suite with security guardrails, line slicing, and diff matching.
"""

import os
import re
import glob
import subprocess
from typing import Dict, Any, Optional

# MARK: - Dangerous Command Detector

DANGEROUS_PATTERNS = [
    r"\brm\s+-[rfRF]{1,4}\s+/\s*($|\s|/|\*)",
    r"\brm\s+-[rfRF]{1,4}\s+~\s*($|\s|/|\*)",
    r"\bmkfs\b",
    r"\bdd\s+if=",
    r"\bchmod\s+-R\s+777\b",
    r"\bchown\s+-R\b",
    r":\(\)\s*\{\s*:\s*\|\s*:\s*&\s*\}\s*;\s*:",  # Fork bomb
    r"\bcurl\s+.*\|\s*(ba)?sh\b",
    r"\bwget\s+.*\|\s*(ba)?sh\b",
    r"\bgit\s+push\s+.*--force\b.*(main|master)",
    r"\bgit\s+reset\s+--hard\b",
]


def is_dangerous_command(command: str) -> Optional[str]:
    """Returns warning reason if command contains dangerous or destructive patterns."""
    for pat in DANGEROUS_PATTERNS:
        if re.search(pat, command, re.IGNORECASE):
            return f"Blocked execution: Matched destructive pattern '{pat}'"
    return None


# MARK: - Native Tool Suite


def run_command(command: str, cwd: str = ".", timeout_sec: float = 30.0) -> Dict[str, Any]:
    """Runs a shell command with security validation and timeout."""
    danger = is_dangerous_command(command)
    if danger:
        return {"exit_code": 1, "output": f"Security Gate Rejection: {danger}"}

    try:
        res = subprocess.run(
            command,
            shell=True,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=timeout_sec,
        )
        out = res.stdout if res.stdout else res.stderr
        return {
            "exit_code": res.returncode,
            "output": out.strip() if out else "(No output)",
        }
    except subprocess.TimeoutExpired:
        return {"exit_code": 124, "output": f"Command timed out after {timeout_sec}s"}
    except Exception as e:
        return {"exit_code": 1, "output": f"Execution error: {str(e)}"}


def view_file(
    path: str, start_line: Optional[int] = None, end_line: Optional[int] = None
) -> Dict[str, Any]:
    """Reads a file with 1-indexed slice notation and line numbering."""
    if not os.path.exists(path):
        return {"success": False, "error": f"File not found: {path}"}

    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            lines = f.readlines()

        total = len(lines)
        s = max(1, start_line) if start_line is not None else 1
        e = min(total, end_line) if end_line is not None else min(total, s + 300)

        sliced = lines[s - 1 : e]
        numbered = [f"{s + i:4d} | {line.rstrip()}" for i, line in enumerate(sliced)]

        return {
            "success": True,
            "path": path,
            "total_lines": total,
            "start_line": s,
            "end_line": e,
            "content": "\n".join(numbered),
        }
    except Exception as e:
        return {"success": False, "error": str(e)}


def replace_file_content(
    path: str, target_content: str, replacement_content: str
) -> Dict[str, Any]:
    """Replaces a precise text block in a file with exact match & whitespace-tolerant fallback."""
    if not os.path.exists(path):
        return {"success": False, "error": f"File not found: {path}"}

    try:
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()

        # 1. Exact match fast-path
        if target_content in content:
            count = content.count(target_content)
            if count > 1:
                return {
                    "success": False,
                    "error": f"Target content matches {count} occurrences. Specify a larger unique block.",
                }
            new_content = content.replace(target_content, replacement_content, 1)
            with open(path, "w", encoding="utf-8") as f:
                f.write(new_content)
            return {
                "success": True,
                "path": path,
                "replaced_bytes": len(replacement_content),
                "match_type": "exact"
            }

        # 2. Whitespace-tolerant line-by-line matching (recovers from small indentation shifts)
        content_lines = content.splitlines(keepends=True)
        target_lines = target_content.splitlines()

        if not target_lines:
            return {"success": False, "error": "Target content is empty."}

        # Strip whitespace for fuzzy scan
        target_stripped = [tl.strip() for tl in target_lines if tl.strip()]
        matches = []

        for i in range(len(content_lines) - len(target_lines) + 1):
            window = content_lines[i : i + len(target_lines)]
            window_stripped = [w.strip() for w in window if w.strip()]
            if window_stripped == target_stripped:
                matches.append((i, i + len(target_lines)))

        if len(matches) == 1:
            start_idx, end_idx = matches[0]
            # Replace the matched lines
            new_lines = content_lines[:start_idx] + [replacement_content + ("\n" if not replacement_content.endswith("\n") else "")] + content_lines[end_idx:]
            with open(path, "w", encoding="utf-8") as f:
                f.writelines(new_lines)
            return {
                "success": True,
                "path": path,
                "replaced_bytes": len(replacement_content),
                "match_type": "fuzzy_whitespace_tolerant",
                "matched_lines": (start_idx + 1, end_idx)
            }
        elif len(matches) > 1:
            return {
                "success": False,
                "error": f"Fuzzy target matched {len(matches)} locations. Include more surrounding lines.",
            }

        # 3. No match found: return closest matching context hint
        return {
            "success": False,
            "error": "Target content not found in file. Check line numbers and exact content.",
            "hint": f"File has {len(content_lines)} total lines."
        }
    except Exception as e:
        return {"success": False, "error": str(e)}


def write_to_file(path: str, code_content: str, overwrite: bool = False) -> Dict[str, Any]:
    """Creates or overwrites a file safely."""
    if os.path.exists(path) and not overwrite:
        return {
            "success": False,
            "error": f"File {path} already exists. Set overwrite=True to replace.",
        }

    try:
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(code_content)
        return {"success": True, "path": path, "bytes_written": len(code_content)}
    except Exception as e:
        return {"success": False, "error": str(e)}


def grep_search(query: str, path: str = ".", is_regex: bool = False) -> Dict[str, Any]:
    """Searches for pattern matches across files in path."""
    matches = []
    try:
        cmd = (
            ["rg", "-n", "--max-count", "30", query, path]
            if not is_regex
            else ["rg", "-n", "-e", query, path]
        )
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=5.0)
        if res.returncode == 0:
            for line in res.stdout.splitlines()[:30]:
                parts = line.split(":", 2)
                if len(parts) >= 3:
                    matches.append(
                        {
                            "file": parts[0],
                            "line": int(parts[1]),
                            "content": parts[2].strip(),
                        }
                    )
            return {"query": query, "matches": matches, "count": len(matches)}
    except Exception:
        pass

    pattern = re.compile(query if is_regex else re.escape(query))
    for root, _, files in os.walk(path):
        if any(ign in root for ign in [".git", ".build", "__pycache__", "dist", "node_modules"]):
            continue
        for file in files:
            full = os.path.join(root, file)
            try:
                with open(full, "r", encoding="utf-8", errors="ignore") as f:
                    for idx, line in enumerate(f, 1):
                        if pattern.search(line):
                            matches.append({"file": full, "line": idx, "content": line.strip()})
                            if len(matches) >= 30:
                                break
            except Exception:
                continue
        if len(matches) >= 30:
            break

    return {"query": query, "matches": matches, "count": len(matches)}


def find_by_name(pattern: str, search_dir: str = ".") -> Dict[str, Any]:
    """Fast glob and file search within directory."""
    results = []
    for root, _, files in os.walk(search_dir):
        if any(ign in root for ign in [".git", ".build", "__pycache__", "dist"]):
            continue
        for file in files:
            if glob.fnmatch.fnmatch(file, pattern):
                results.append(os.path.join(root, file))
                if len(results) >= 40:
                    break
        if len(results) >= 40:
            break
    return {"pattern": pattern, "results": results, "count": len(results)}


TOOLS_SCHEMAS = [
    {
        "type": "function",
        "name": "run_command",
        "description": "Execute a shell command in the workspace with safety controls.",
        "parameters": {
            "type": "object",
            "properties": {"command": {"type": "string", "description": "Shell command to run"}},
            "required": ["command"],
        },
    },
    {
        "type": "function",
        "name": "view_file",
        "description": "Read file contents with line numbers and optional line slicing.",
        "parameters": {
            "type": "object",
            "properties": {
                "path": {
                    "type": "string",
                    "description": "Relative or absolute file path",
                },
                "start_line": {
                    "type": "integer",
                    "description": "Starting line number (1-indexed)",
                },
                "end_line": {
                    "type": "integer",
                    "description": "Ending line number (inclusive)",
                },
            },
            "required": ["path"],
        },
    },
    {
        "type": "function",
        "name": "replace_file_content",
        "description": "Replace an exact chunk of text in an existing file.",
        "parameters": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "File path to modify"},
                "target_content": {
                    "type": "string",
                    "description": "Exact text to find and replace",
                },
                "replacement_content": {
                    "type": "string",
                    "description": "New replacement text",
                },
            },
            "required": ["path", "target_content", "replacement_content"],
        },
    },
    {
        "type": "function",
        "name": "write_to_file",
        "description": "Create a new file with specified content.",
        "parameters": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Target file path"},
                "code_content": {"type": "string", "description": "Full file content"},
                "overwrite": {
                    "type": "boolean",
                    "description": "Allow overwriting existing file",
                },
            },
            "required": ["path", "code_content"],
        },
    },
    {
        "type": "function",
        "name": "grep_search",
        "description": "Search code files for pattern or text occurrences.",
        "parameters": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Search string or regex pattern",
                },
                "path": {
                    "type": "string",
                    "description": "Search directory (default .)",
                },
            },
            "required": ["query"],
        },
    },
    {
        "type": "function",
        "name": "find_by_name",
        "description": "Find files by glob pattern.",
        "parameters": {
            "type": "object",
            "properties": {
                "pattern": {
                    "type": "string",
                    "description": "Filename glob pattern (e.g. *.swift)",
                }
            },
            "required": ["pattern"],
        },
    },
]


def dispatch_tool(name: str, arguments: Dict[str, Any]) -> str:
    """Dispatches a tool call by name and returns structured JSON result."""
    if name == "run_command":
        res = run_command(arguments.get("command", ""))
    elif name == "view_file":
        res = view_file(
            arguments.get("path", ""),
            start_line=arguments.get("start_line"),
            end_line=arguments.get("end_line"),
        )
    elif name == "replace_file_content":
        res = replace_file_content(
            arguments.get("path", ""),
            arguments.get("target_content", ""),
            arguments.get("replacement_content", ""),
        )
    elif name == "write_to_file":
        res = write_to_file(
            arguments.get("path", ""),
            arguments.get("code_content", ""),
            overwrite=bool(arguments.get("overwrite", False)),
        )
    elif name == "grep_search":
        res = grep_search(arguments.get("query", ""), path=arguments.get("path", "."))
    elif name == "find_by_name":
        res = find_by_name(arguments.get("pattern", "*"))
    else:
        res = {"error": f"Unknown tool: {name}"}

    import json

    return json.dumps(res)
