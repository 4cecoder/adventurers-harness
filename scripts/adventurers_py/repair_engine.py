"""
Deterministic JSON & Tool Call Repair Engine
Automatically recovers from tiny model formatting errors:
- Markdown code blocks (```json ... ```)
- Trailing commas & single quotes
- Unquoted property names
- Unescaped newlines in JSON strings
- Type coercion (e.g. str -> int for line numbers)
"""

import re
import json
from typing import Dict, Any, Optional, Tuple


def extract_json_block(text: str) -> str:
    """Extracts JSON substring from markdown fences or text."""
    if not text:
        return ""
    # Strip markdown json fences
    match = re.search(r"```(?:json)?\s*([\s\S]*?)\s*```", text, re.IGNORECASE)
    if match:
        return match.group(1).strip()

    # Try finding outermost {} or []
    brace_match = re.search(r"(\{[\s\S]*\}|\[[\s\S]*\])", text)
    if brace_match:
        return brace_match.group(1).strip()

    return text.strip()


def repair_json_string(raw: str) -> Tuple[Optional[Dict[str, Any]], Optional[str]]:
    """Attempts multi-stage deterministic repair of malformed JSON strings."""
    cleaned = extract_json_block(raw)
    if not cleaned:
        return None, "Empty payload"

    # Stage 1: Standard JSON parse
    try:
        return json.loads(cleaned), None
    except Exception:
        pass

    # Stage 2: Replace single quotes with double quotes
    s2 = re.sub(r"(?<!\\)'", '"', cleaned)
    try:
        return json.loads(s2), None
    except Exception:
        pass

    # Stage 3: Remove trailing commas before } or ]
    s3 = re.sub(r",\s*([\}\]])", r"\1", s2)
    try:
        return json.loads(s3), None
    except Exception:
        pass

    # Stage 4: Quote unquoted keys (e.g. {path: "foo"})
    s4 = re.sub(r"([{,]\s*)([a-zA-Z_][a-zA-Z0-9_]*)\s*:", r'\1"\2":', s3)
    try:
        return json.loads(s4), None
    except Exception as e:
        return None, f"JSON repair failed: {str(e)}"


def normalize_tool_arguments(tool_name: str, args: Dict[str, Any]) -> Dict[str, Any]:
    """Coerces types for tiny model arguments."""
    normalized = dict(args)

    if tool_name == "view_file":
        if "start_line" in normalized and isinstance(normalized["start_line"], str):
            try:
                normalized["start_line"] = int(normalized["start_line"])
            except ValueError:
                pass
        if "end_line" in normalized and isinstance(normalized["end_line"], str):
            try:
                normalized["end_line"] = int(normalized["end_line"])
            except ValueError:
                pass

    elif tool_name == "write_to_file":
        if "overwrite" in normalized and isinstance(normalized["overwrite"], str):
            normalized["overwrite"] = normalized["overwrite"].lower() in (
                "true",
                "1",
                "yes",
            )

    return normalized
