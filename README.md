# Adventurers Harness

[![macOS Apple Silicon](https://img.shields.io/badge/macOS-Apple%20Silicon%20(ARM64)-orange?logo=apple)](https://github.com/4cecoder/adventurers-harness/releases/download/latest/Adventurers-macOS-arm64.dmg)
[![CI Status](https://github.com/4cecoder/adventurers-harness/actions/workflows/ci.yml/badge.svg)](https://github.com/4cecoder/adventurers-harness/actions/workflows/ci.yml)
[![GitHub Pages](https://img.shields.io/badge/Docs-GitHub%20Pages-blue)](https://4cecoder.github.io/adventurers-harness/)
[![Homebrew Tap](https://img.shields.io/badge/Homebrew-4cecoder%2Fadventurers-yellow?logo=homebrew)](https://github.com/4cecoder/adventurers-harness)

> A native macOS coding agent harness built in Swift 6. The model proposes work. The harness certifies completion.

---

## ⚡ Direct Download & Installation

### Option 1: Homebrew (Recommended)
```bash
# Tap and install from public repository
brew tap 4cecoder/adventurers https://github.com/4cecoder/adventurers-harness
brew install adventurers

# Launch from anywhere
adventurers
```

### Option 2: Direct macOS ARM64 Disk Image (DMG)
Download the latest continuous build from GitHub Actions:
- **[⬇️ Download Adventurers-macOS-arm64.dmg (Latest)](https://github.com/4cecoder/adventurers-harness/releases/download/latest/Adventurers-macOS-arm64.dmg)**
- **[📦 Download Adventurers-macOS-arm64.zip](https://github.com/4cecoder/adventurers-harness/releases/download/latest/Adventurers-macOS-arm64.zip)**
- **[🗜 Download Adventurers-macOS-arm64.tar.gz](https://github.com/4cecoder/adventurers-harness/releases/download/latest/Adventurers-macOS-arm64.tar.gz)**

---

## Philosophy

**The model never decides it is done.** Programmatic gates (syntax, repeat, compilation, structural) certify completion. Inspired by the autoreverse project's deterministic gate pipeline and adapted for a general-purpose coding agent.

## Architecture

```
Sources/
├── GUI/                    # Native macOS SwiftUI application (Obsidian Glass Theme)
│   ├── AdventurersApp.swift    # App entry, three-panel layout
│   ├── AppUpdateManager.swift  # In-app GitHub update checker & 1-click installer
│   ├── ThreadListView.swift    # Sidebar: parallel agent threads
│   ├── ThreadView.swift        # Center: chat, code blocks, mode switcher
│   ├── GateProgressView.swift  # 6-Gate certification pipeline visualization
│   ├── DiffViewer.swift        # Side-by-side/unified diff review & preflight patcher
│   ├── SkillsPanel.swift       # Skill library management
│   ├── PermissionDialog.swift  # Risk-level tool approval system
│   ├── TerminalOutputView.swift# Interactive terminal with self-development quick chips
│   ├── WorkbenchStatusBar.swift# Real-time sliding window TPS & telemetry chips
│   ├── SettingsView.swift      # Engine, Cloud Plans, Meta-Harness, and Gates settings
│   ├── Theme.swift             # Design system: colors, typography, spacing
│   └── Components.swift        # Reusable UI component library
├── AdventurersCore/        # Core harness engine
│   ├── Protocols.swift         # LLMProvider, Tool, Gate protocols
│   ├── AgentLoop.swift         # Propose → Gate → Certify cycle
│   ├── TaskContract.swift      # Immutable task boundaries & budgets
│   ├── StateEngine.swift       # FSM with enforced transitions
│   ├── Gates.swift             # 6 deterministic certification gates
│   ├── DarwinSandbox.swift     # Kernel-enforced Seatbelt sandbox profiles
│   ├── MetaHarness.swift       # Multi-agent subprocess execution engine
│   ├── MeteringTelemetry.swift # 1.2s sliding window token velocity & cost ledger
│   ├── DiffEngine.swift        # Context-matching atomic diff preflight & patcher
│   ├── TrajectoryCompressor.swift # Anchor-preserving history compactor
│   ├── FailChain.swift         # Escalating capsule feedback engine
│   └── EventJournal.swift      # Append-only JSONL event store
├── LLMProviders/           # Universal multi-model cloud streaming (OpenCode, Claude, GPT, GLM)
├── Tools/                  # Sandboxed File, Bash, Glob, Grep tools
└── Tests/                  # 14/14 unit test suite
```

## Key Design Patterns

| Pattern | Description |
|---|---|
| **The Model Proposes, The Harness Certifies** | LLM never decides completion. Deterministic gates certify. |
| **Deterministic 6-Gate Pipeline** | Syntax → Repeat → Compilation → Diff → Memory → Objective |
| **Darwin Seatbelt Sandboxing** | Kernel-enforced read/write isolation for bash & file tools |
| **Multi-Agent Meta-Dispatch** | Run external sub-agent CLIs (Codex, Hermes, OpenCode, dsh, Pi, smallctl) |
| **Sliding Window TPS Telemetry** | 1.2s rolling token velocity, TTFT latency, and multi-model cost ledger |
| **Escalating FailChain Feedback** | Same failure 3x gets progressively stern escalation capsules |
| **Contract-Based Budget** | Immutable `TaskContract` with turn and token limits |
| **In-App GitHub Auto-Updates** | Continuous release monitoring, release note viewer, and 1-click DMG installer |

## Getting Started

```bash
# Build and run locally
swift build
swift run Adventurers

# Run unit tests
swift test
```

## Build & Release Packaging (macOS ARM64)

```bash
# Generate high-resolution Apple standard .icns from SVG
./scripts/generate_icon.sh

# Build, codesign, and package Adventurers.app, DMG installer, and ZIP/TAR archives
./scripts/package_app.sh 1.0.0
```

Output artifacts in `dist/`:
- `dist/Adventurers.app` (macOS Application Bundle)
- `dist/Adventurers-macOS-arm64.dmg` (Disk Image Installer)
- `dist/Adventurers-macOS-arm64.tar.gz` (Homebrew Distribution Tarball)
- `dist/Adventurers-macOS-arm64.zip` (Distribution Archive)
- `dist/*.sha256` (Integrity Checksums)

## CI / CD Pipeline

Automated via GitHub Actions:
- **`CI (macOS ARM64)`**: Runs full 14-test suite on native `macos-15` Apple Silicon runners.
- **`Build & Package macOS ARM64`**: Builds release DMG, ZIP, and TAR archives on every push to `master` and tag.
- **`Deploy to GitHub Pages`**: Deploys website to [`https://4cecoder.github.io/adventurers-harness/`](https://4cecoder.github.io/adventurers-harness/).

## License

MIT
