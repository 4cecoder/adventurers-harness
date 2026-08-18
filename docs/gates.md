# Gate System

## Philosophy

> The model proposes. The harness certifies.

Gates are deterministic checks that evaluate agent output without using any LLM. They are the trust boundary between the model's proposal and the harness's certification.

## Gate Pipeline

```
SyntaxGate → RepeatGate → CompilationGate → [MemoryGate] → [ObjectiveGate]
```

Required gates must pass for task completion. Optional gates provide additional verification.

## Gate Definitions

### SyntaxGate (required)

Validates code structure:
- Balanced braces `{}` / `}`
- Balanced parentheses `()` / `)`
- Extracts code from markdown fences
- No empty output detection

**Failure feedback**: "Unbalanced braces: 3 open, 2 close"

### RepeatGate (required)

Prevents infinite loops:
- Hashes each output (MD5)
- Compares against all previous outputs in the task
- Rejects verbatim identical submissions

**Failure feedback**: "Identical submission to a previous round"

### CompilationGate (optional)

Compiles the output:
- For Swift: `swiftc` syntax check
- For other languages: appropriate compiler
- Validates the code can be compiled

**Failure feedback**: "Compilation error: expected '}' at line 42"

### MemoryGate (optional, domain-specific)

Validates hardware addresses (for reverse engineering tasks):
- Checks GBA memory map
- Validates register addresses
- Detects out-of-range memory access

### ObjectiveGate (optional)

Structural verification without LLM:
- Counts function calls
- Counts control flow structures
- Compares structure against expected patterns

## Escalating Feedback (FailChain)

When the same gate fails repeatedly, feedback escalates:

| Consecutive Failures | Feedback Level |
|---------------------|----------------|
| 1 | Gentle hint: "Gate failed, please review" |
| 2 | Stern directive: "Failed AGAIN, try different approach" |
| 3+ | Critical escalation: "STOP repeating, do X/Y/Z" |

This prevents the LLM from looping on the same broken approach.

## Gate Results

Each gate returns a `GateResult`:

```swift
struct GateResult {
    let passed: Bool
    let gateName: String
    let output: String    // human-readable result
    let error: String?    // failure reason
}
```

## Configuring Required Gates

In `TaskContract`:

```swift
TaskContract(
    prompt: "Implement feature X",
    maxRounds: 4,
    requiredGates: ["syntax", "repeat"]  // must pass these
)
```

Optional gates (compilation, memory, objective) can be added for additional verification.
