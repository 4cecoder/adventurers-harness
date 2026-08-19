# Adventurers Harness Architecture

## Overview

Adventurers Harness is a native macOS application written in Swift 6 that serves as a deterministic coding agent harness and multi-harness dispatcher. It manages multiple AI coding agents running in parallel, providing a unified interface for task orchestration, code review, sandbox security, and programmatic gate certification.

---

## Documentation Index

- [**Harness Engineering Guide**](harness-engineering-guide.md) — Comprehensive principles for reliable coding agent harnesses.
- [**Meta-Harness Dispatcher**](meta-harness-dispatch.md) — Multi-agent CLI orchestration and credential isolation.
- [**Gate Certification System**](gates.md) — The 6-gate deterministic verification pipeline.
- [**Real-Time Telemetry & Metering**](telemetry-and-metering.md) — Rolling TPS tracking, TTFT metrics, and cost estimation.
- [**UI Design System**](design-system.md) — Obsidian theme, liquid glass components, and typography.
- [**Reference Projects**](reference-projects.md) — Architectural taxonomy of leading agent implementations.

---

## Core Philosophy

**The model proposes. The harness certifies.**

The LLM never decides when a task is complete. Instead, a pipeline of deterministic gates (syntax checking, repeat detection, compilation, structural verification, path safety) certifies completion. This completely prevents hallucinated completion states.

---

## Module Architecture

### 1. `AdventurersCore`
The central execution engine:
- **`AgentLoop`**: The propose → gate → certify execution cycle.
- **`MetaHarness`**: Dispatcher for external CLI agents (`codex`, `hermes`, `opencode`, `dsh`, `pi`, `smallctl`).
- **`TaskContract`**: Immutable task boundaries with round budgets.
- **`StateEngine`**: Finite state machine with strictly enforced transitions.
- **`Gates`**: Deterministic verification checks (`SyntaxGate`, `RepeatGate`, `CompilationGate`, `DiffGate`, `MemoryGate`, `ObjectiveGate`).
- **`FailChain`**: Escalating capsule feedback for repeated failures.
- **`EventJournal`**: Append-only JSONL event ledger for replay and debugging.
- **`DiffEngine`**: Unified and side-by-side patch computation and atomic file application.
- **`DarwinSandbox`**: Kernel-level Seatbelt sandboxing via `sandbox-exec` profiles.
- **`TrajectoryCompressor`**: Context compaction preserving task anchors and summarizing execution traces.
- **`MeteringTelemetry`**: Token throughput accounting, pricing schedules, and context headroom gauges.

### 2. `GUI`
Native macOS SwiftUI 6 application:
- **`AdventurersApp`**: Three-panel workbench layout (sidebar, editor/thread, inspector).
- **`ThreadListView`**: Parallel multi-agent thread management.
- **`ThreadView`**: Streaming chat, code blocks, diff viewer, and quick mode switcher.
- **`WorkbenchStatusBar`**: Real-time rolling TPS, TTFT latency, active engine chip, and context headroom meter.
- **`GateProgressView`**: Live gate certification visualization.
- **`SettingsView`**: Settings modal with dedicated Execution Mode, Coding Plan Keys, and Meta-Harness CLI tabs.
- **`TerminalOutputView`**: Full-width adaptive terminal stream.

### 3. `LLMProviders`
Frontier cloud provider client with native Server-Sent Events (SSE) streaming and tool call parsing for OpenCode, Anthropic, OpenAI, DeepSeek, Z.AI GLM, and OpenRouter.

### 4. `Tools`
Built-in sandboxed tools: `bash`, `view_file`, `write_file`, `edit_file`, `list_dir`, `grep_search`, `glob`.

---

## Data Flow

```
User Input / Task Contract
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│                     Execution Mode Router                   │
└──────────────┬───────────────────────────────┬──────────────┘
               │                               │
       [Coding Plan Mode]              [Meta Harness Mode]
               │                               │
               ▼                               ▼
    UniversalCloudProvider             MetaHarnessRunner
     (Direct API Stream)              (CLI Subprocess Pipe)
               │                               │
               └───────────────┬───────────────┘
                               │
                               ▼
                    Sandboxed Tool Execution
                               │
                               ▼
               Deterministic Gate Certification
               ├── SyntaxGate (Balanced code blocks)
               ├── RepeatGate (SHA-256 loop prevention)
               ├── DiffGate (Path security & destructive check)
               ├── CompilationGate (Native toolchain check)
               ├── MemoryGate (Domain boundaries)
               └── ObjectiveGate (AST structural metrics)
                               │
               ┌───────────────┴───────────────┐
               ▼                               ▼
        All Gates Pass?                  Gate Failed?
               │                               │
         [SUCCESS]                     [FAIL-CHAIN]
     Certify & Finalize              Escalate Feedback
                                      & Loop back to Model
```

