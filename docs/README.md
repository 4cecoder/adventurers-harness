# Adventurers Harness Documentation Index

Comprehensive guides, specifications, and reverse-engineering analyses for **Adventurers Harness**.

---

## 📚 Documentation Sitemap

### 1. Getting Started & Core Concepts
- [**Getting Started Quickstart**](getting-started.md) — 30-second setup, build instructions, and first run.
- [**Apple Silicon MLX Unified Memory Optimization**](mlx-unified-memory-optimization.md) — 1-bit Bonsai 27B (~5GB), high-TPS small models, and zero-copy UMA memory budgets.
- [**System Architecture & Engine**](architecture.md) — FSM lifecycle, proposal-certification loop, and actor model.
- [**Inference Paradigms**](inference-paradigms.md) — Subscriptions vs API keys vs Meta-Harness CLI dispatch.
- [**Harness Engineering Guide**](harness-engineering-guide.md) — Swift 6 concurrency, actor isolation, and coding standards.

### 2. Safety, Sandboxing & Verification
- [**Deterministic 6-Gate Pipeline & Sandbox**](gates.md) — Syntax, Repeat, Compilation, Diff, Memory, and Objective gates.
- [**Guardian Circuit Breaker & Fail-Closed Safety**](guardian-and-safety.md) — Dual-threshold anomaly trips, dangerous command detector, and execution policy.

### 3. Durability, Storage & Recovery
- [**Session Durability, JSONL & Checkpoint Rollbacks**](durability-and-checkpoints.md) — Append-only event streaming, crash recovery, and 1-click snapshot restore.
- [**Telemetry & Multi-Model Cost Metering**](telemetry-and-metering.md) — Sliding window TPS velocity, TTFT latency, and token ledger.

### 4. Knowledge & Modular Skills
- [**Open Knowledge Format (OKF) & Skills**](okf-knowledge-packets.md) — High-velocity knowledge packets and skills without MCP bloat.

### 5. UI & Design System
- [**Obsidian Glass Design System**](design-system.md) — macOS Sequoia native visual styling, typography, and color tokens.

### 6. Reverse Engineering & Strategic Plans
- [**Muse Improvement Plan**](muse-improvement-plan.md) — Complete 10-feature adoption plan from Muse 0.2.1-R1215.1 binary analysis.
- [**Implementation Details Minutia**](implementation-details.md) — 10 critical sections with decision trees, fail-closed safety, and token limits.
- [**Codex Architecture Disassembly**](codex-architecture.md) — Analysis of Codex Mach-O binary and RS engine.
- [**IDA Pro Reverse Engineering Methodology**](ida-reverse-engineering.md) — Step-by-step disassembly guide for AI coding agent binaries.
- [**Comparative Reference Projects**](reference-projects.md) — Feature survey across existing agents.
- [**Engineering Roadmap**](roadmap.md) — Phased milestone schedule (v1.0 to v2.5).

---

*Adventurers Harness — Built with Swift 6 for macOS Apple Silicon.*
