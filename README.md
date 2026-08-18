# Adventurers Harness

> A native macOS coding agent harness built in Swift 6. The model proposes work. The harness certifies completion.

## Philosophy

**The model never decides it is done.** Programmatic gates (syntax, repeat, compilation, structural) certify completion. Inspired by the autoreverse project's deterministic gate pipeline and adapted for a general-purpose coding agent.

## Architecture

```
Sources/
├── GUI/                    # Native macOS SwiftUI application
│   ├── AdventurersApp.swift    # App entry, three-panel layout
│   ├── ThreadListView.swift    # Sidebar: parallel agent threads
│   ├── ThreadView.swift        # Center: chat, code blocks, tool calls
│   ├── GateProgressView.swift  # Gate certification visualization
│   ├── DiffViewer.swift        # Side-by-side/unified diff review
│   ├── SkillsPanel.swift       # Skill library management
│   ├── PermissionDialog.swift  # Tool permission system
│   ├── TerminalOutputView.swift# Command output panel
│   ├── SettingsView.swift      # Full settings window
│   ├── Theme.swift             # Design system: colors, typography, spacing
│   └── Components.swift        # Reusable UI component library
├── AdventurersCore/        # Core harness engine
│   ├── Protocols.swift         # LLMProvider, Tool, Gate protocols
│   ├── AgentLoop.swift         # Propose → Gate → Certify cycle
│   ├── TaskContract.swift      # Immutable task boundaries
│   ├── StateEngine.swift       # FSM with enforced transitions
│   ├── Gates.swift             # SyntaxGate, RepeatGate, CompilationGate
│   ├── FailChain.swift         # Escalating capsule feedback
│   └── EventJournal.swift      # Append-only JSONL event store
├── LLMProviders/           # Provider abstraction (empty, building)
├── Tools/                  # Built-in tools (empty, building)
└── Tests/
```

## Key Design Patterns (from autoreverse)

| Pattern | Description |
|---------|-------------|
| **Model Proposes, Harness Certifies** | LLM never decides completion. Gates certify. |
| **Deterministic Gate Pipeline** | Syntax → Repeat → Compilation → Memory → Objective |
| **Escalating Capsule Feedback** | Same gate failing 3x gets increasingly stern |
| **Contract-Based Budget** | Immutable `TaskContract` with max rounds |
| **Event Journal** | Append-only JSONL for replay and debugging |
| **FSM State Engine** | Enforced state transitions, no illegal moves |
| **Leaf-First Ordering** | Implement dependencies before dependents |

## Reference Projects (in `research/`)

- **Codex** (OpenAI) — Rust CLI agent, gate-based certification
- **Hermes Agent** (Nous Research) — Self-improving agent with learning loop
- **Pi** (earendil-works) — Multi-provider TypeScript harness
- **OpenCode** (opencode-ai) — Go CLI with LSP, SQLite sessions
- **DeepSeek Harness** — Plugin-everything architecture
- **SmallCTL** — Staged workflow phases, FAMA failure mitigation
- **Little-Coder** — Optimized for small (7B-35B) models

## UI Design (inspired by Codex Desktop App)

- **Three-panel layout**: Sidebar (threads) → Content (chat/diff) → Inspector (gates/tools)
- **Multi-agent parallel threads**: Each task runs in its own thread
- **Gate progress visualization**: Real-time certification pipeline
- **Skills library**: Extend capabilities with bundled instructions
- **Permission system**: Risk-level-based tool approval
- **Diff review**: Side-by-side and unified diff viewers

## Getting Started

```bash
swift build
swift run Adventurers
```

## License

MIT
