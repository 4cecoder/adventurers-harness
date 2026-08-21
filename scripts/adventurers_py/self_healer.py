"""
Deterministic Self-Healing Feedback Capsule Generator
When a tiny model's tool call fails (syntax error, file not found, bad arguments),
this engine formats a high-density, 1-shot repair prompt so the small model
can auto-correct on the very next turn with 0 token waste.
"""

from typing import Dict, Any, Optional

def generate_repair_capsule(
    tool_name: str,
    failed_args: Dict[str, Any],
    error_message: str,
    file_context: Optional[str] = None
) -> str:
    """Creates a concise surgical correction guidance string for tiny models."""
    capsule = [
        f"[SYSTEM GATE REPAIR GUIDANCE]",
        f"Tool '{tool_name}' failed with error: {error_message}"
    ]

    if tool_name == "replace_file_content":
        capsule.append("• Action Required: View lines of the target file first using `view_file` to confirm exact content.")
        if file_context:
            capsule.append(f"• File Context:\n{file_context[:300]}")

    elif tool_name == "view_file":
        capsule.append("• Action Required: Ensure `path` exists and `start_line` / `end_line` are positive integers.")

    elif tool_name == "run_command":
        capsule.append("• Action Required: Check command syntax or ensure required tools/files exist.")

    capsule.append("Propose corrected tool call arguments now.")
    return "\n".join(capsule)
