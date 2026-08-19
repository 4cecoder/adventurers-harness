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
# Build and run locally
swift build
swift run Adventurers

# Run unit tests
swift test
```

## Build & Release Packaging (macOS ARM64)

Adventurers Harness includes a vector icon build pipeline and automated packager:

```bash
# Generate high-resolution Apple standard .icns from SVG
./scripts/generate_icon.sh

# Build, codesign, and package Adventurers.app, DMG installer, and ZIP archive
./scripts/package_app.sh 1.0.0
```

Output artifacts in `dist/`:
- `dist/Adventurers.app` (macOS Application Bundle)
- `dist/Adventurers-macOS-arm64.dmg` (Disk Image Installer)
- `dist/Adventurers-macOS-arm64.zip` (Distribution Archive)
- `dist/Adventurers-macOS-arm64.dmg.sha256` (Integrity Checksum)

## CI / CD Pipeline

Automated via GitHub Actions in [`.github/workflows/build-macos-arm64.yml`](.github/workflows/build-macos-arm64.yml):
- Native Apple Silicon runner (`macos-14` / `arm64`)
- Validates Swift 6 build & 13 unit tests
- Renders SVG icon to multi-resolution `.icns`
- Builds and packages `.app`, `.dmg`, and `.zip`
- Publishes automated GitHub releases with checksums on `v*` tags

## License

MIT
