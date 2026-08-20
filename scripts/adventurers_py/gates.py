"""
Adventurers Python Safety & Verification Gates
Semi-deterministic verification before applying edits or continuing loops.
"""

from typing import List, Dict, Any, Optional

class SyntaxGate:
    """Checks balanced braces, brackets, and quotes in modified code."""
    @staticmethod
    def verify(text: str) -> (bool, Optional[str]):
        stack = []
        pairs = {')': '(', '}': '{', ']': '['}
        
        # Simple token scan outside string literals
        in_string = False
        str_char = None
        escaped = False

        for idx, char in enumerate(text):
            if escaped:
                escaped = False
                continue
            if char == '\\':
                escaped = True
                continue
            if char in ('"', "'", '`'):
                if in_string and char == str_char:
                    in_string = False
                elif not in_string:
                    in_string = True
                    str_char = char
                continue
            if in_string:
                continue

            if char in '({[':
                stack.append((char, idx))
            elif char in ')}]':
                if not stack:
                    return False, f"Unmatched closing '{char}' at index {idx}"
                top, _ = stack.pop()
                if pairs[char] != top:
                    return False, f"Mismatched closing '{char}' (expected closing for '{top}')"

        if stack:
            unclosed, pos = stack[-1]
            return False, f"Unclosed opening '{unclosed}' at index {pos}"

        return True, None

class RepeatGate:
    """Detects repetitive tool thrashing in the agent loop."""
    def __init__(self, max_repeats: int = 3):
        self.history: List[str] = []
        self.max_repeats = max_repeats

    def record_and_check(self, tool_name: str, arguments: Dict[str, Any]) -> (bool, Optional[str]):
        import json
        key = f"{tool_name}:{json.dumps(arguments, sort_keys=True)}"
        self.history.append(key)
        
        # Count consecutive identical actions
        count = 0
        for item in reversed(self.history):
            if item == key:
                count += 1
            else:
                break

        if count >= self.max_repeats:
            return False, f"Repeat Gate Tripped: Tool '{tool_name}' called {count} times consecutively with identical arguments."
        return True, None

class DiffGate:
    """Verifies safety of proposed file replacements."""
    @staticmethod
    def verify(target_content: str, replacement_content: str) -> (bool, Optional[str]):
        if not target_content or target_content.strip() == "":
            return False, "Diff Gate: Target content cannot be empty."
        if target_content == replacement_content:
            return False, "Diff Gate: Target and replacement content are identical (no-op)."
        return True, None

class GuardianCircuitBreaker:
    """Stops the loop if too many consecutive failures occur."""
    def __init__(self, max_failures: int = 3):
        self.max_failures = max_failures
        self.consecutive_failures = 0
        self.is_tripped = False

    def record_outcome(self, success: bool):
        if success:
            self.consecutive_failures = 0
        else:
            self.consecutive_failures += 1
            if self.consecutive_failures >= self.max_failures:
                self.is_tripped = True

    def reset(self):
        self.consecutive_failures = 0
        self.is_tripped = False
