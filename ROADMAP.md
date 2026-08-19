# Adventurers Harness — Architectural Roadmap

> **North Star**: Build the most dependable, deterministic, and high-velocity macOS-native coding agent harness on Apple Silicon.  
> **Core Principle**: *The model proposes. The harness certifies.*

---

## 🗺️ Milestone Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  v1.0.0 (SHIPPED)                                                           │
│  • Swift 6 Three-Panel Obsidian Glass UI                                    │
│  • 6-Gate Deterministic Certification Engine                                │
│  • Darwin Seatbelt Kernel Sandboxing                                        │
│  • Multi-Agent Meta-Harness Subprocess Dispatch                             │
│  • 1.2s Sliding Window TPS Metering & Telemetry                             │
│  • In-App GitHub Releases Auto-Updater                                      │
│  • Homebrew Formula/Cask & GitHub Pages Site                                │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Phase 2: Agent Mesh & Local Intelligence (v1.1.0 – v1.3.0)                │
│  • Native PTY Pseudo-Terminal with Full ANSI/VT100 Emulation                │
│  • SourceKit-LSP & Multi-Language Server Protocol Integration                │
│  • Local Vector Corpus Embedding & Fast Codebase Search                      │
│  • Autonomous Self-Development Dogfooding Loop                              │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Phase 3: Extensible Gate Plugins & Team Workspaces (v1.4.0 – v1.6.0)       │
│  • WebAssembly / Swift Gate Plugin Architecture                             │
│  • Visual 3-Way Diff Resolution & Atomic Rollback Engine                    │
│  • Team Gate Policies & Attestation Sync                                    │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Phase 4: Autonomous Harness Evolution (v2.0.0+)                           │
│  • Self-Hosting Optimization under Immutable Verification Gates             │
│  • Live SWE-bench Verified & HumanEval GUI Evaluator                        │
│  • Multi-Machine Decentralized Harness Mesh                                 │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## ✅ Completed in v1.0.0

- [x] **Native macOS 15+ Apple Silicon Architecture**: Pure Swift 6 with strict concurrency safety and SwiftUI 3-panel workspace.
- [x] **6-Gate Deterministic Engine**:
  - `SyntaxGate`: Bracket, syntax, and block balance validation.
  - `RepeatGate`: Loop and repetitive output detection.
  - `CompilationGate`: Non-destructive preflight build verification.
  - `DiffGate`: High-risk command inspection and protected file fencing.
  - `MemoryGate`: POSIX `getrusage` memory usage bounding.
  - `ObjectiveGate`: Contract objective and budget verification.
- [x] **FailChain Escalation Engine**: Progressive 3-tier feedback capsules for persistent errors.
- [x] **Darwin Seatbelt Sandboxing**: Kernel-level sandbox profiles for bash and file operations.
- [x] **Multi-Agent Meta-Harness Dispatch**: Process-isolated orchestration for `codex`, `hermes`, `opencode`, `dsh`, `pi`, and `smallctl` CLIs.
- [x] **Real-Time Sliding Window Telemetry**: 1.2s token velocity (TPS), Time-to-First-Token (TTFT), and multi-model cost ledger.
- [x] **In-App GitHub Auto-Updater**: Continuous release monitoring, rendered release notes, and 1-click DMG mounting.
- [x] **Homebrew Distribution**: `Formula/adventurers.rb` & `Casks/adventurers.rb` with verified SHA256 checksums.
- [x] **Automated CI/CD & GitHub Pages**: GitHub Actions Apple Silicon (`macos-15`) test/packaging workflows and live landing site.

---

## 🚀 Phase 2: Agent Mesh & Local Intelligence (v1.1.0 – v1.3.0)

### 1. Native PTY Pseudo-Terminal Engine
- [ ] Replace standard process pipes with a native macOS Pseudo-Terminal (PTY via `openpty`/`forkpty`).
- [ ] Full VT100 / xterm-256color rendering supporting interactive curses tools (`htop`, `vim`, `less`, `tig`).
- [ ] Direct bi-directional agent stdin piping for interactive confirmation dialogues.

### 2. Language Server Protocol (LSP) Integration
- [ ] Native Swift client for `SourceKit-LSP` (Swift/C/C++), `zls` (Zig), `rust-analyzer` (Rust), and `pyright` (Python).
- [ ] Real-time compiler diagnostics fed directly into `CompilationGate` without requiring full disk builds.
- [ ] AST symbol navigation and symbol-aware contextual code insertion.

### 3. Local Vector Corpus Indexing & Semantic Code Search
- [ ] In-memory vector database with lightweight sqlite-vec persistence.
- [ ] Local embedding generation (e.g. `nomic-embed-text` or Apple Accelerate ML embeddings).
- [ ] Context-aware prompt injection referencing relevant symbol definitions and architectural docs.

---

## 🛡️ Phase 3: Extensible Gate Plugins & Teams (v1.4.0 – v1.6.0)

### 1. WebAssembly & Dynamic Gate Plugins
- [ ] Wasmtime-powered gate runner enabling developers to write custom gates in Rust, Go, Python, or TypeScript.
- [ ] Gate marketplace / repository tap for sharing domain-specific gates (e.g., Security/OWASP Gate, License Compliance Gate, Performance Regression Gate).

### 2. Visual 3-Way Diff & Atomic Rollback
- [ ] Interactive 3-way conflict resolver for concurrent multi-agent file modifications.
- [ ] Tree-sitter powered semantic diffing highlighting AST alterations rather than raw text lines.
- [ ] Instant snapshot restore points powered by atomic APFS copy-on-write cloning.

### 3. Team Gate Policy Sync
- [ ] Organization-wide gate policies committed as `.adventurers/gates.json` in repositories.
- [ ] CI preflight enforcement sharing identical certification rules between local GUI and remote GitHub Actions.

---

## 🔮 Phase 4: Autonomous Harness Evolution (v2.0.0+)

### 1. Self-Hosted Harness Optimization
- [ ] Autonomous self-improvement loop: Adventurers Harness refactors, optimizes, and tests its own codebase under immutable certification contracts.
- [ ] Automated regression benching comparing version latency, memory footprint, and token velocity against historical baselines.

### 2. Live SWE-bench & Benchmark Evaluator
- [ ] Built-in benchmark harness to run SWE-bench Verified, HumanEval, and custom internal evaluation suites directly from the macOS GUI.
- [ ] Side-by-side agent comparison matrix (e.g. Claude 3.7 Sonnet vs OpenAI Codex vs DeepSeek R1).

---

## 🤝 Contributing & Community

Adventurers Harness is open-source under the MIT license. We welcome contributions to gates, providers, tools, and UI components!

- **Repository**: [`https://github.com/4cecoder/adventurers-harness`](https://github.com/4cecoder/adventurers-harness)
- **Documentation**: [`https://4cecoder.github.io/adventurers-harness/`](https://4cecoder.github.io/adventurers-harness/)
- **Bug Reports & Issues**: [`https://github.com/4cecoder/adventurers-harness/issues`](https://github.com/4cecoder/adventurers-harness/issues)
