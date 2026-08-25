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
│   ├── AdventurersApp.swift    # App entry, three-panel workspace layout
│   ├── ThreadView.swift        # Root container wiring gate bar, messages, and input
│   ├── ThreadViewModel.swift   # Observable state, tool executor, snapshots & recovery
│   ├── ThreadMessageRow.swift  # Message bubbles, rich markdown, and syntax code blocks
│   ├── ToolClusterViews.swift  # Auto-collapsing multi-tool clusters and indicators
│   ├── MessageInputBar.swift   # Glass input bar, native text editor & prompt queue
│   ├── CompactGateBar.swift    # Compact gate status lights & workspace selector
│   ├── TaskContractProgressCard.swift # Long-horizon phase contract and 1-click rollback
│   ├── GateProgressView.swift  # Deterministic certification pipeline drawer
│   ├── DiffViewer.swift        # Side-by-side/unified diff review & preflight patcher
│   ├── SkillsPanel.swift       # Skill library management
│   ├── PermissionDialog.swift  # Risk-level tool approval system
│   ├── WorkbenchStatusBar.swift# Real-time sliding window TPS & telemetry meters
│   └── Theme.swift             # Obsidian glass styling, fonts & gradients
├── AdventurersCore/        # Core harness engine
│   ├── Protocols.swift         # LLMProvider, Tool, Gate protocols
│   ├── AgentLoop.swift         # Propose → Gate → Certify cycle
│   ├── DangerousCommandDetector.swift # Banned patterns, wrapped shell & sudo inspector
│   ├── ExecPolicy.swift        # Layered allow/deny/askApproval execution engine
│   ├── ToolApproval.swift      # Session tokens, rejection counters & auto-escalation
│   ├── NetworkGate.swift       # Protocol filter (HTTPS) and wildcard domain allowlist
│   ├── TaskJudger.swift        # Semi-deterministic turn optimizer (fastDirect vs longHorizon)
│   ├── AlignmentGriller.swift  # Ambiguity detection & clarification probe generator
│   ├── SessionCheckpointEngine.swift # Atomic workspace file snapshotting & rollback
│   ├── TaskContractManager.swift # Long-horizon task contract, phases & checklists
│   ├── ContextCompactor.swift  # Anchor-preserving (head/tail) context compactor
│   ├── StateEngine.swift       # FSM with strictly enforced transitions
│   ├── Gates.swift             # Deterministic verification gate pipeline
│   ├── DarwinSandbox.swift     # Kernel-enforced Seatbelt sandbox profiles
│   ├── MetaHarness.swift       # Multi-agent subprocess execution engine
│   ├── MeteringTelemetry.swift # 1.2s sliding window token velocity & cost ledger
│   ├── DiffEngine.swift        # Context-matching atomic diff preflight & patcher
│   ├── ThreadMessageConsolidator.swift # Proximity-based multi-tool message consolidator
│   └── FailChain.swift         # Escalating capsule feedback engine
├── LLMProviders/           # Universal multi-model cloud streaming (OpenCode, Claude, GPT, GLM)
├── Tools/                  # Sandboxed File, Bash, Glob, Grep tools
└── Tests/                  # Modular test suites by domain (7 suites, 28+ tests)
```

## Documentation

- 📖 [**Complete Documentation Sitemap**](docs/README.md)
- 🚀 [**Getting Started (30s Quickstart)**](docs/getting-started.md)
- ⚡ [**Apple Silicon MLX Unified Memory Optimization (1-bit 5GB Bonsai & Swarm)**](docs/mlx-unified-memory-optimization.md)
- 🧠 [**The 3 Inference Paradigms**](docs/inference-paradigms.md)
- 🛡️ [**Deterministic 6-Gate Pipeline & Sandbox**](docs/gates.md)
- ⚡ [**Guardian Circuit Breaker & Fail-Closed Safety**](docs/guardian-and-safety.md)
- 💾 [**Session Durability, JSONL & Checkpoint Rollbacks**](docs/durability-and-checkpoints.md)
- 📦 [**Open Knowledge Format (OKF) & Skills**](docs/okf-knowledge-packets.md)
- 🔌 [**Meta-Harness CLI Sub-Agent Dispatch**](docs/meta-harness-dispatch.md)
- 📊 [**Telemetry & Multi-Model Cost Metering**](docs/telemetry-and-metering.md)
- 🎯 [**Muse Improvement Plan**](docs/muse-improvement-plan.md)
- 🔍 [**Reverse Engineering Minutia & Implementation Details**](docs/implementation-details.md)
- 🗺️ [**Engineering Roadmap (v1.0 to v2.5)**](ROADMAP.md)

## Key Design Patterns

| Pattern | Description |
|---|---|
| **The Model Proposes, The Harness Certifies** | LLM never decides completion. Deterministic gates certify. |
| **Deterministic 6-Gate Pipeline** | Syntax → Repeat → Compilation → Diff → Memory → Objective |
| **Darwin Seatbelt Sandboxing** | Kernel-enforced read/write isolation for bash & file tools |
| **Multi-Agent Meta-Dispatch** | Run external sub-agent CLIs (Antigravity `agy`, Claude Code `claude`, Codex, Hermes, OpenCode, dsh) |
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

---

## 📦 Build & Install

Full guide: [docs/install.md](docs/install.md)

```bash
./scripts/run_dev_app.sh     # Debug build wrapped in a proper .app bundle (mic permissions work)
./scripts/package_app.sh     # Release build → dist/Adventurers.app + DMG/ZIP/TAR.GZ + sha256
./scripts/install_local.sh   # Install dist/Adventurers.app to /Applications and launch
```
