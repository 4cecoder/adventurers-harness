# Agent Harness Engineering Guide

> A comprehensive architectural reference for building reliable, deterministic, high-throughput AI coding agent harnesses.

---

## 1. Core Paradigm: Model Proposes, Harness Certifies

The foundational flaw of unconstrained AI agents is allowing the model to decide when it has completed a task. Large Language Models frequently suffer from premature termination, phantom test successes, and hallucinated completion declarations.

### The Trust Boundary
- **The Model is an Untrusted Generator**: The LLM proposes plans, code changes, tool calls, and patch blocks.
- **The Harness is a Deterministic Verifier**: The harness evaluates changes against strict programmatic gates (syntax parsers, AST validators, atomic compilers, file-diff safety filters, and test runners).
- **Completion Requires Hard Proof**: The agent cannot exit the execution loop until every required deterministic gate produces a passing cryptographic or programmatic assertion.

```
┌────────────────────────────────────────────────────────┐
│                      AGENT LOOP                        │
│                                                        │
│  User Task Contract (Immutable Budget & Boundaries)     │
│        │                                               │
│        ▼                                               │
│  ┌───────────┐       Propose Patches & Actions         │
│  │    LLM    │ ─────────────────────────────────────┐  │
│  │ Generator │ ◄─────────────────────────────────┐  │  │
│  └───────────┘       Escalating Fail-Chain       │  │  │
│                      (Capsule Feedback)          │  │  │
│                                                  │  ▼  │
│                                     ┌────────────────┐ │
│                                     │  Deterministic │ │
│                                     │  Certification │ │
│                                     │     Gates      │ │
│                                     └───────┬────────┘ │
│                                             │          │
│                      All Gates Pass?        │          │
│                      ├── YES ──► Task Certified (Exit) │
│                      └── NO  ──► Record Fail State     │
└────────────────────────────────────────────────────────┘
```

---

## 2. Multi-Tier Execution Modes: Coding Plan vs. Meta-Harness

A modern agent harness should support dual execution strategies to balance speed, cost, and specialization:

### Tier 1: Direct Coding Plan Mode
- **Engine**: Direct HTTP/SSE streaming connection to frontier LLM APIs (OpenCode, Anthropic Claude, OpenAI, DeepSeek, Z.AI GLM, OpenRouter).
- **Control**: The harness directly executes local read/write tools (`view_file`, `edit_file`, `bash`, `grep`, `glob`) inside a sandboxed environment.
- **Telemetry**: Fine-grained per-token metrics (real-time rolling TPS, TTFT latency, cost tracking in USD).
- **Use Case**: Fast interactive iterations, incremental edits, unit test fixing, and code review.

### Tier 2: Meta-Harness Delegation Mode
- **Engine**: Spawns and manages external specialized sub-agent CLI binaries (e.g., OpenAI Codex CLI, Nous Hermes Agent, OpenCode CLI, DeepSeek Harness `dsh`, Pi Harness, SmallCTL).
- **Isolation**: Each harness runs in its own child subprocess with isolated working directories, dedicated API keys, and custom environment variable injections (`CODEX_API_KEY`, `HERMES_API_KEY`, etc.).
- **Process Supervision**: Captures line-by-line streaming stdout/stderr, enforces timeout budgets, and evaluates results with harness certification gates.
- **Use Case**: Complex multi-step migrations, autonomous repository reverse engineering, and multi-model consensus workflows.

---

## 3. Deterministic Gate Pipelines

Gates evaluate agent output without invoking another LLM, eliminating recursive hallucinations.

| Gate | Type | Method | Rejection Condition |
|------|------|--------|---------------------|
| **SyntaxGate** | Required | Lexer / Parser Token Scanner | Unbalanced braces `{}` or parentheses `()`, malformed JSON, empty code blocks |
| **RepeatGate** | Required | Content SHA-256 Digest Ledger | Re-submitting identical proposals across consecutive turns |
| **DiffGate** | Required | Path & AST Safety Inspector | Modifications outside allowed workspace, destructive commands (`rm -rf /`), accessing sensitive files (`.ssh`, `.aws`) |
| **CompilationGate** | Required | Native Toolchain Compiler | Code fails `swift build`, `tsc`, `rustc`, or language compiler |
| **MemoryGate** | Domain | Range & Pointer Validation | Out-of-bounds register or buffer addressing |
| **ObjectiveGate** | Optional | Structural AST Metrics | Missing required exported symbols, failure to meet contract assertions |

---

## 4. Escalating Feedback Loops (The Fail-Chain)

When an agent fails a certification gate, returning raw error messages often causes the model to loop on the same failing strategy. The **FailChain** implements progressive escalation:

1. **Round 1 (Gentle Diagnostic)**:
   - *"SyntaxGate Failed: Unbalanced curly brace at line 42. Please check nesting."*
2. **Round 2 (Stern Directive)**:
   - *"SyntaxGate Failed AGAIN (Attempt #2): You are repeating the same structural defect. Do NOT repeat the previous block. Re-read the file structure before emitting code."*
3. **Round 3+ (Critical Intervention / Fallback)**:
   - *"CRITICAL FAILURE: 3 consecutive gate rejections. The harness has frozen edits. You must switch strategy immediately or propose a localized patch."*

---

## 5. Hermetic Sandboxing & Safety

Security cannot rely on model alignment. Agent harnesses must enforce host operating system security controls:

- **Apple Darwin Seatbelt (`sandbox-exec`)**: Enforces kernel-level file read/write restrictions, preventing access to user directories (`~/.ssh`, `~/.aws`, `/etc`, system binaries).
- **Workspace Confinement**: Resolves all relative paths against the project root with canonicalized symlink verification to prevent directory traversal (`../../`).
- **Command Whitelisting & Blocklisting**: Pre-screens bash commands, rejecting dangerous primitives (`sudo`, `mkfs`, fork bombs) before execution.

---

## 6. Trajectory Token Compression & Memory Anchoring

As multi-turn conversations grow, context windows become saturated, increasing latency and cost. 

### Preservation Rules
1. **System Prompt & Task Contract**: Always preserved intact (Anchor Priority 100).
2. **First User Prompt**: Always preserved to maintain task intent (Anchor Priority 90).
3. **Active Working State**: The most recent $N$ turns are kept in full fidelity.
4. **Intermediate Tool Logs**: Compressed into concise semantic summaries:
   - `42 lines of compiler output` → `[Compiler: 1 error in File.swift:42]`
   - `150 lines of grep results` → `[Grep: 3 matches in Sources/Core/]`

---

## 7. Real-Time Telemetry & Pricing Ledger

A research-grade harness provides transparent insight into generation dynamics:

- **Rolling TPS Window**: Computes real-time tokens per second using a high-precision sliding timestamp window ($1.2\text{s}$).
- **Time-to-First-Token (TTFT)**: Measures millisecond latency from dispatch to initial chunk.
- **Context Headroom Health**:
  - `🟢 Optimal (<50%)`
  - `🔵 Moderate (50–70%)`
  - `🟡 High Load (70–85%)`
  - `🔴 Compaction Recommended (>85%)`
- **Model Pricing Ledger**: Calculates live USD spend based on exact input, output, and reasoning token pricing matrices.
