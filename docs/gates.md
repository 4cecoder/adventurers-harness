# Gate Certification System

> The model proposes. The harness certifies.

Gates are deterministic programmatic checks that evaluate agent proposals without using any LLM. They form the trust boundary between the model's proposals and the host codebase.

---

## The 6-Gate Certification Pipeline

```
┌────────────┐   ┌────────────┐   ┌─────────────────┐   ┌────────────┐   ┌────────────┐   ┌───────────────┐
│ SyntaxGate │──►│ RepeatGate │──►│ CompilationGate │──►│  DiffGate  │──►│ MemoryGate │──►│ ObjectiveGate │
└────────────┘   └────────────┘   └─────────────────┘   └────────────┘   └────────────┘   └───────────────┘
```

Every task specifies required gates in its `TaskContract`. When all required gates pass, the task is certified and finalized.

---

## Gate Definitions

### 1. SyntaxGate (Required)
Validates source code structural integrity:
- **Balanced Braces & Parentheses**: Scans `{}` and `()` token balance across proposed code blocks.
- **Markdown Code Fence Extraction**: Safely extracts language snippets (`swift`, `rust`, `python`, `typescript`, `go`).
- **Empty Output Prevention**: Rejects whitespace-only or truncated completions.
- **Diagnostic Feedback**: `"Unbalanced braces: 3 open, 2 close. Missing closing brace before end of file."`

### 2. RepeatGate (Required)
Prevents hallucination infinite loops:
- **SHA-256 Content Fingerprinting**: Computes cryptographically stable hashes of all submitted patches and code blocks.
- **Cycle Detection**: Detects if the agent is cycling between identical previous failed attempts.
- **Diagnostic Feedback**: `"Identical submission detected (hash: a3f8...). Please modify your implementation strategy."`

### 3. DiffGate (Security & Policy)
Inspects file modifications and command executions before application:
- **Workspace Boundary Enforcement**: Prevents directory traversal attacks (`../../etc/passwd`).
- **Sensitive Path Guard**: Blocks reads/writes to `~/.ssh`, `~/.aws`, `~/.gnupg`, `id_rsa`, `.env.local`.
- **Destructive Command Guard**: Catches destructive primitives (`rm -rf /`, `mkfs`, `sudo`, `dd if=/dev/zero`).

### 4. CompilationGate (Domain / Toolchain)
Runs language toolchain diagnostics:
- For Swift: Invokes `swift build` or `swiftc -typecheck`.
- For Rust: Invokes `cargo check`.
- For TypeScript: Invokes `tsc --noEmit`.
- **Diagnostic Feedback**: Surfaces exact compiler error lines, warnings, and missing symbols back into the agent context.

### 5. MemoryGate (Domain-Specific)
Validates hardware and low-level memory maps:
- Verifies base addresses and memory boundaries.
- Detects segmentation violations and out-of-range register offsets.

### 6. ObjectiveGate (Structural Verification)
Asserts declarative contract conditions without secondary LLM calls:
- Verifies presence of newly exported public API symbols.
- Asserts AST function call counts and test suite pass rates.

---

## Escalating Feedback (FailChain)

When a gate rejects an agent's proposal across consecutive turns, `FailChain` prevents the agent from persisting with broken assumptions:

| Consecutive Failures | Escalation Level | Feedback Tone |
|----------------------|------------------|---------------|
| **1 Failure** | Gentle Diagnostic | Contextual hint with line number and syntax error snippet. |
| **2 Failures** | Stern Directive | Explicit warning against repeating previous patterns; instructions to inspect imports/types. |
| **3+ Failures** | Critical Intervention | Freezes iterative loop; mandates strategy pivot or localized diff patch. |

---

## TaskContract Configuration

Gates are defined declaratively in the immutable `TaskContract`:

```swift
let contract = TaskContract(
    prompt: "Implement Darwin Seatbelt sandbox bindings in Swift",
    maxRounds: 6,
    requiredGates: [
        GateIdentifier.syntax.rawValue,
        GateIdentifier.repeatCheck.rawValue,
        GateIdentifier.compilation.rawValue,
        GateIdentifier.diff.rawValue
    ]
)
```

