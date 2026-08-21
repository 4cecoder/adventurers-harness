"""
Deterministic Context Optimizer & Token Budget Compactor
Preserves critical Head (contract) and Tail (recency) anchors while crushing middle turns
to keep context safely within tiny model attention windows (< 2,000 tokens).
"""

from typing import List, Dict, Any


def estimate_tokens(text: str) -> int:
    """Fast rule-of-thumb token estimator (approx 4 chars/token)."""
    return max(1, len(text) // 4)


def compact_tool_output(tool_name: str, output_str: str, max_chars: int = 240) -> str:
    """Summarizes lengthy tool outputs into structured single-line milestones."""
    if len(output_str) <= max_chars:
        return output_str

    lines = output_str.strip().splitlines()
    if len(lines) > 4:
        first_line = lines[0][:80]
        last_line = lines[-1][:80]
        return (
            f"[{tool_name} returned {len(lines)} lines]: {first_line} ... {last_line}"
        )
    return output_str[:max_chars] + " ... [truncated]"


class ContextOptimizer:
    def __init__(self, max_token_budget: int = 1500, tail_turns_preserved: int = 2):
        self.max_token_budget = max_token_budget
        self.tail_turns_preserved = tail_turns_preserved

    def optimize_messages(self, messages: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Compacts message history if exceeding token budget."""
        if len(messages) <= 3:
            return messages

        total_text = " ".join(m.get("content", "") or "" for m in messages)
        estimated = estimate_tokens(total_text)

        if estimated <= self.max_token_budget:
            return messages

        # Anchor 1: Head (First message / System Prompt)
        head = [messages[0]]

        # Anchor 2: Tail (Last N turns)
        tail_start_idx = max(1, len(messages) - self.tail_turns_preserved)
        tail = messages[tail_start_idx:]

        # Middle Window: Compact intermediate turns
        middle = messages[1:tail_start_idx]
        compacted_middle = []

        for m in middle:
            role = m.get("role", "assistant")
            content = m.get("content", "") or ""
            compacted_content = compact_tool_output("turn", content, max_chars=120)
            compacted_middle.append(
                {"role": role, "content": f"[COMPACTED]: {compacted_content}"}
            )

        return head + compacted_middle + tail
