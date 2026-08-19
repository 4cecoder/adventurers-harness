# Adventurers Harness — Bulletproof Architectural Roadmap

> **North Star**: Build the most dependable, deterministic, and high-velocity macOS-native coding agent harness on Apple Silicon.
> **Core Principle**: *The model proposes. The harness certifies.*
> **Evidence Base**: IDA Pro disassembly of Codex 212MB Mach-O ARM64 binary (2,720 strings, 5 classified subsystems) + codex-rs source inspection.

---

## High-Level Milestone Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Phase 1: Foundation & Deterministic Gates (v1.0.0 — COMPLETED & TESTED)    │
│  • Swift 6 Three-Panel Obsidian Glass UI                                    │
│  • 6-Gate Deterministic Certification Pipeline                              │
│  • Darwin Seatbelt Kernel Sandboxing                                        │
│  • Multi-Agent Meta-Harness Subprocess Dispatch                             │
│  • 1.2s Sliding Window TPS Metering & Telemetry                             │
│  • In-App GitHub Releases Auto-Updater & Homebrew Formula                   │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Phase 2: Bulletproof Core Engine (v1.1 – v1.3)                              │
│  • Rule-Based Execution Policy Engine (Codex-style .rules files)            │
│  • Granular Tool Approval Escalation (per-tool + per-session overrides)     │
│  • Network Permission Gate (protocol-level allow/deny)                      │
│  • SQLite-Backed Structured State Persistence                               │
│  • Context Compaction v2 with Anchor Preservation                           │
│  • Layered Config System (CLI → env → workspace → user → defaults)          │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Phase 3: Local Intelligence, PTY & LSP (v1.4 – v1.6)                       │
│  • POSIX PTY Pseudo-Terminal with Full ANSI/VT100 Emulation                │
│  • SourceKit-LSP & Multi-Language Server Protocol Integration               │
│  • Real-Time In-Memory CompilationGate (no disk writes)                     │
│  • Local Vector Corpus Embedding & Fast Codebase Search                     │
│  • APFS Copy-on-Write Atomic Snapshot Rollbacks                             │
│  • Autonomous Self-Development Dogfooding Loop                              │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Phase 4: Extensible Gate Plugins & Team Policies (v1.7 – v2.0)             │
│  • WebAssembly (Wasmtime) & Swift Dynamic Gate Plugin Architecture          │
│  • Visual 3-Way Diff Resolution & Conflict Resolver                         │
│  • Repository .adventurers/gates.json Policy Parser                         │
│  • Team Gate Attestation CLI & GitHub PR Checks Annotations                 │
│  • OWASP Security & Credential Gate Plugin                                  │
│  • OpenTelemetry OTLP Export Pipeline                                       │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Phase 5: Autonomous Self-Modification & Eval Matrix (v2.1 – v2.5)          │
│  • Self-Hosting Optimization under Immutable Verification Gates             │
│  • Live SWE-bench Verified & HumanEval GUI Evaluator                        │
│  • Hardware Telemetry (Apple Neural Engine, Metal GPU, Thermal State)       │
│  • Plugin Marketplace with Git-Based Distribution                           │
│  • Hotspot Optimizer for User Code                                          │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Phase 6: Multi-Agent Mesh & Distributed Swarm (v2.6.0+)                    │
│  • Actor-Based Agent Mesh Protocol with P2P Unix Sockets                    │
│  • Live Swarm Network Topology Graph & Work-Stealing Task Queue             │
│  • Multi-Machine Apple Silicon Distributed Cluster Execution                │
│  • CRDT Shared Context Blackboard                                           │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Foundation & Core Engine (`v1.0.0` — Completed & Verified)

- [x] **Task 1.1: Three-Panel SwiftUI Desktop Architecture**
  - **Files**: `Sources/GUI/AdventurersApp.swift`, `Sources/GUI/ThreadListView.swift`, `Sources/GUI/ThreadView.swift`
  - **Acceptance Criteria**: Fluid 3-panel layout, Obsidian Glass design system, 60 FPS streaming.
  - **Microtests**: Passed `stateEngineFullLifecycle` and UI state bindings.

- [x] **Task 1.2: 6-Gate Deterministic Certification Pipeline**
  - **Files**: `Sources/AdventurersCore/Gates.swift`, `Sources/AdventurersCore/Protocols.swift`
  - **Gates**: Syntax, Repeat, Compilation, Diff, Memory, Objective.
  - **Microtests**: All 5 gate microtests passed.

- [x] **Task 1.3: Darwin Seatbelt Kernel Sandboxing**
  - **Files**: `Sources/AdventurersCore/DarwinSandbox.swift`
  - **Acceptance Criteria**: 3-tier sandbox profiles (read-only, workspace-write, danger-full-access).
  - **Microtests**: Passed `darwinSandboxPathAccess`.

- [x] **Task 1.4: Pure Swift Streaming Patch & Diff Engine**
  - **Files**: `Sources/AdventurersCore/DiffEngine.swift`
  - **Acceptance Criteria**: Unified diff parser, preflight conflict detection, atomic patch applier.
  - **Microtests**: Passed `diffEngineMultiHunk` and `diffEngineCorruptedContext`.

- [x] **Task 1.5: Sliding Window TPS Telemetry & Multi-Model Cost Ledger**
  - **Files**: `Sources/AdventurersCore/MeteringTelemetry.swift`, `Sources/GUI/WorkbenchStatusBar.swift`
  - **Acceptance Criteria**: 1.2s rolling token velocity, TTFT tracking, context headroom, multi-tier pricing.
  - **Microtests**: Passed `modelPricingMultiTier` and `turnMetricsAccounting`.

- [x] **Task 1.6: Multi-Agent Meta-Harness Dispatch**
  - **Files**: `Sources/AdventurersCore/MetaHarness.swift`, `Sources/GUI/SettingsView.swift`
  - **Acceptance Criteria**: Process isolation, custom CLI mappings for 8 external harnesses.
  - **Microtests**: Passed `metaHarnessRegistryDiscovery`.

- [x] **Task 1.7: In-App GitHub Releases Auto-Updater & Homebrew Packaging**
  - **Files**: `Sources/GUI/AppUpdateManager.swift`, `scripts/package_app.sh`
  - **Acceptance Criteria**: Semver comparison, 1-click installer, Homebrew formula.

---

## Phase 2: Bulletproof Core Engine (`v1.1 – v1.3`)

> Derived from Codex reverse engineering findings. These features close the gaps identified in `docs/codex-architecture.md`.

- [ ] **Task 2.1: Rule-Based Execution Policy Engine**
  - **Target File**: `Sources/AdventurersCore/ExecPolicy.swift`
  - **Description**: Replace binary `RiskLevel` with a rule-based permission evaluator inspired by Codex's `codex_execpolicy`. Supports `.adventurers/rules` files with granular allow/deny/escalate decisions per command pattern.
  - **Acceptance Criteria**:
    - Rule file parser with `allow`, `deny`, `ask_for_approval` decisions
    - Command pattern matching (prefix, regex, glob)
    - Per-rule timeout and working directory constraints
    - Policy layering: defaults → user → workspace → project
  - **Microtest**: `execPolicyRuleMatchingAndEscalation()`
  - **Codex Reference**: `codex-rs/execpolicy/src/`, `core/src/exec_policy.rs`

- [ ] **Task 2.2: Granular Tool Approval Escalation System**
  - **Target File**: `Sources/AdventurersCore/ToolApproval.swift`
  - **Description**: Replace simple `RiskLevel` enum with per-tool, per-session approval overrides. Inspired by Codex's `ExecApprovalRequestEvent` and `ApplyPatchApprovalRequestEvent` patterns.
  - **Acceptance Criteria**:
    - Per-tool approval policy (always_allow, always_deny, ask_every_time, ask_once_per_session)
    - Approval request/response cycle with timeout
    - Session-level approval caching
    - Escalation from `ask` to `deny` after N consecutive rejections
  - **Microtest**: `toolApprovalEscalationAndSessionCaching()`
  - **Codex Reference**: `core/src/guardian/approval_request.rs`, `tools/sandboxing/`

- [ ] **Task 2.3: Network Permission Gate**
  - **Target File**: `Sources/AdventurersCore/NetworkGate.swift`
  - **Description**: Add network protocol-level permission checking to the gate pipeline. Codex evaluates `allow`/`deny` per `http-connect`/`https_connect` protocol. Add as Gate #7.
  - **Acceptance Criteria**:
    - Protocol-level filtering (HTTP, HTTPS, WebSocket, Unix socket)
    - Per-host allow/deny rules
    - SOCKS5 proxy support
    - Integration with gate pipeline as `NetworkGate`
  - **Microtest**: `networkGateProtocolFiltering()`
  - **Codex Reference**: `core/src/network_policy_decision.rs`, `core/src/exec_policy.rs`

- [ ] **Task 2.4: SQLite-Backed Structured State Persistence**
  - **Target File**: `Sources/AdventurersCore/StateStore.swift`
  - **Description**: Replace JSONL `EventJournal` with SQLite-backed state persistence. Codex uses `state_db` for thread metadata and `rollout` files for conversation state.
  - **Acceptance Criteria**:
    - SQLite database with WAL mode for concurrent reads
    - Thread state persistence (goal, messages, gate results)
    - Rollout serialization/deserialization
    - Migration support for schema evolution
  - **Microtest**: `stateStorePersistenceAndMigration()`
  - **Codex Reference**: `core/src/state_db_bridge.rs`, `core/src/rollout.rs`, `thread-store/`

- [ ] **Task 2.5: Context Compaction v2 with Anchor Preservation**
  - **Target File**: `Sources/AdventurersCore/ContextCompactor.swift`
  - **Description**: Upgrade `TrajectoryCompressor` to match Codex's `compact_remote_v2` with structured anchor preservation, token budget awareness, and role alternation validity.
  - **Acceptance Criteria**:
    - Head anchor: system prompt + task contract (protected)
    - Tail anchor: last N turns (protected)
    - Middle compaction with structured summary (not just truncation)
    - Token budget pre-check before compaction trigger
    - Role alternation validation (user/assistant/tool must alternate)
  - **Microtest**: `contextCompactorAnchorPreservationAndRoleValidity()`
  - **Codex Reference**: `core/src/compact_remote_v2.rs`, `core/src/compact_token_budget.rs`

- [ ] **Task 2.6: Layered Configuration System**
  - **Target File**: `Sources/AdventurersCore/ConfigStack.swift`
  - **Description**: Replace flat `HarnessConfig` with Codex-style 5-layer config stack: CLI args → environment variables → workspace `.adventurers/config.toml` → user `~/.adventurers/config.toml` → built-in defaults.
  - **Acceptance Criteria**:
    - TOML config file parsing
    - Layer precedence with merge semantics
    - Environment variable interpolation
    - Config schema validation
    - Hot-reload on file change
  - **Microtest**: `configStackLayerPrecedenceAndMerge()`
  - **Codex Reference**: `core/src/config/`, `codex-config/`

- [ ] **Task 2.7: Dangerous Command Detection Engine**
  - **Target File**: `Sources/AdventurersCore/DangerousCommandDetector.swift`
  - **Description**: Port Codex's `codex_shell_command::is_dangerous_command` pattern — a curated list of dangerous command prefixes with context-aware matching.
  - **Acceptance Criteria**:
    - Shell wrapper detection (bash, zsh, fish, sh, osascript)
    - Package runner detection (npm run, cargo, bun)
    - Destructive command detection (dd, mkfs, rm -rf, chmod -R 777)
    - Pipe-to-shell detection (curl | sh, wget | bash)
    - Integration with DiffGate and ExecPolicy
  - **Microtest**: `dangerousCommandDetectionComprehensive()`
  - **Codex Reference**: `core/src/exec_policy.rs` (BANNED_PREFIX_SUGGESTIONS), `shell-command/`

- [ ] **Task 2.8: Phase 2 Microtest Test Suite Expansion**
  - **Target File**: `Tests/AdventurersCoreTests/Phase2Microtests.swift`
  - **Description**: Comprehensive unit test suite covering Tasks 2.1 through 2.7.

---

## Phase 3: Local Intelligence, PTY & LSP (`v1.4 – v1.6`)

- [ ] **Task 3.1: POSIX PTY Pseudo-Terminal Subsystem**
  - **Target File**: `Sources/GUI/TerminalPTY.swift`
  - **Description**: Replace basic `Process` pipes with native macOS Pseudo-Terminal (`openpty`/`forkpty`).
  - **Acceptance Criteria**: Master/slave FDs, window resize (`TIOCSWINSZ`), raw terminal modes.
  - **Microtest**: `terminalPTYAllocationAndResize()`

- [ ] **Task 3.2: Streamed ANSI / VT100 Escape Sequence Parser**
  - **Target File**: `Sources/GUI/TerminalANSIParser.swift`
  - **Description**: Fast tokenizing state machine for ANSI color codes, cursor movements, text styles.
  - **Acceptance Criteria**: 256-color, 24-bit TrueColor, zero frame drops.
  - **Microtest**: `ansiParserColorsAndCursorEscapeCodes()`

- [ ] **Task 3.3: Bi-Directional Interactive Stdin Controller**
  - **Target File**: `Sources/GUI/TerminalStdinController.swift`
  - **Description**: Forward user keystrokes (Ctrl+C, Ctrl+D, arrows, Tab) into running processes.
  - **Acceptance Criteria**: vim, htop, git rebase -i respond interactively.
  - **Microtest**: `terminalStdinKeystrokePiping()`

- [ ] **Task 3.4: JSON-RPC 2.0 Asynchronous Transport Engine**
  - **Target File**: `Sources/LSP/JSONRPCTransport.swift`
  - **Description**: Pure Swift async/await JSON-RPC 2.0 framed transport for LSP.
  - **Acceptance Criteria**: Content-Length headers, request/notification/response serialization.
  - **Microtest**: `jsonRpcFramingAndMessageDispatch()`

- [ ] **Task 3.5: Native SourceKit-LSP Client Connection**
  - **Target File**: `Sources/LSP/SourceKitLSPClient.swift`
  - **Description**: Launch and manage background `/usr/bin/sourcekit-lsp` server.
  - **Acceptance Criteria**: initialize, didOpen, didChange, real-time diagnostics.
  - **Microtest**: `sourceKitLSPInitializeAndDiagnostics()`

- [ ] **Task 3.6: Real-Time In-Memory LSP CompilationGate**
  - **Target File**: `Sources/AdventurersCore/LSPCompilationGate.swift`
  - **Description**: Preflight Swift changes against SourceKit-LSP diagnostics without disk writes.
  - **Acceptance Criteria**: Rejects syntax/type errors in <50ms.
  - **Microtest**: `lspCompilationGateSubSecondPreflight()`

- [ ] **Task 3.7: Multi-Language LSP Support Matrix**
  - **Target File**: `Sources/LSP/MultiLanguageLSPManager.swift`
  - **Description**: Auto-detect project language, connect to rust-analyzer, zls, pyright.
  - **Acceptance Criteria**: Polyglot compiler diagnostics.
  - **Microtest**: `multiLanguageLSPDiscoveryAndBinding()`

- [ ] **Task 3.8: SQLite Vector Embedding Store**
  - **Target File**: `Sources/Corpus/VectorStore.swift`
  - **Description**: Embedded SQLite vector storage with Cosine similarity indexing.
  - **Acceptance Criteria**: 1536-dim embeddings, sub-5ms nearest-neighbor queries.
  - **Microtest**: `vectorStoreInsertionAndCosineQuery()`

- [ ] **Task 3.9: Semantic AST Code Chunker**
  - **Target File**: `Sources/Corpus/ASTChunker.swift`
  - **Description**: Split code along AST boundaries (classes, structs, functions).
  - **Acceptance Criteria**: Preserves function signatures and docstrings.
  - **Microtest**: `astChunkerPreservesSignaturesAndContext()`

- [ ] **Task 3.10: Apple Accelerate BNNS Local Embeddings Engine**
  - **Target File**: `Sources/Corpus/LocalEmbeddingEngine.swift`
  - **Description**: Run lightweight embedding models on Apple Silicon Neural Engine / Metal.
  - **Acceptance Criteria**: >500 chunks/sec offline, 0 network latency.
  - **Microtest**: `localEmbeddingGenerationSpeedAndAccuracy()`

- [ ] **Task 3.11: APFS Copy-on-Write Atomic Snapshot Rollbacks**
  - **Target File**: `Sources/AdventurersCore/APFSSnapshot.swift`
  - **Description**: Leverage macOS APFS `clonefile()` for zero-cost instant workspace snapshots.
  - **Acceptance Criteria**: Sub-10ms snapshot creation, atomic rollback on gate rejection.
  - **Microtest**: `apfsSnapshotCreationAndRollback()`

- [ ] **Task 3.12: Self-Hosted Dogfooding Loop**
  - **Target File**: `Sources/GUI/DogfoodManager.swift`
  - **Description**: Adventurers Harness uses its own tools to inspect, build, test, and package itself.
  - **Acceptance Criteria**: Self-dev quick chips trigger complete certification pipeline.
  - **Microtest**: `dogfoodPipelineExecutionAndSelfCheck()`

- [ ] **Task 3.13: Phase 3 Microtest Test Suite Expansion**
  - **Target File**: `Tests/AdventurersCoreTests/Phase3Microtests.swift`

---

## Phase 4: Extensible Gate Plugins & Team Policies (`v1.7 – v2.0`)

- [ ] **Task 4.1: Wasmtime WebAssembly Gate Runner**
  - **Target File**: `Sources/AdventurersCore/WasmGateRunner.swift`
  - **Description**: Embed Wasmtime to execute custom gate binaries in sandbox.
  - **Acceptance Criteria**: <64MB memory quota, <500ms instruction timeout.
  - **Microtest**: `wasmGateExecutionAndTimeoutBounding()`

- [ ] **Task 4.2: Standard Gate WASI Interface Protocol**
  - **Target File**: `Sources/AdventurersCore/WasiGateInterface.swift`
  - **Description**: C/WASI ABI for custom gates in Rust, Go, TypeScript, Swift.
  - **Acceptance Criteria**: JSON via stdin, GateResult JSON from stdout.
  - **Microtest**: `wasiGateInterfaceJsonSerialization()`

- [ ] **Task 4.3: Repository `.adventurers/gates.json` Policy Parser**
  - **Target File**: `Sources/AdventurersCore/GatePolicyLoader.swift`
  - **Description**: Declarative gate config committed in repos.
  - **Acceptance Criteria**: Required gates, timeouts, memory limits, custom WASM paths.
  - **Microtest**: `gatePolicyJsonSchemaValidation()`

- [ ] **Task 4.4: Visual 3-Way Merge Conflict Resolver**
  - **Target File**: `Sources/GUI/DiffMergeView.swift`
  - **Description**: Interactive 3-pane merge UI (Ours / Base / Theirs).
  - **Acceptance Criteria**: Visual hunk selection, manual editing, 1-click acceptance.
  - **Microtest**: `threeWayMergeConflictDetection()`

- [ ] **Task 4.5: Tree-Sitter Semantic AST Diff Visualizer**
  - **Target File**: `Sources/GUI/SemanticDiff.swift`
  - **Description**: Highlight renamed variables, moved functions, altered type signatures.
  - **Acceptance Criteria**: Distinguishes structural from superficial changes.
  - **Microtest**: `semanticDiffAstAlterationDetection()`

- [ ] **Task 4.6: Team Gate Attestation CLI**
  - **Target File**: `Sources/CLI/GateCheckCommand.swift`
  - **Description**: Run 6-gate pipeline in GitHub Actions / GitLab CI.
  - **Acceptance Criteria**: Exit 0 on clean, non-zero with SARIF output.
  - **Microtest**: `cliGateCheckCommandExecution()`

- [ ] **Task 4.7: GitHub PR Checks API Annotations Reporter**
  - **Target File**: `Sources/CLI/GitHubChecksReporter.swift`
  - **Description**: Post gate results as line annotations on GitHub PRs.
  - **Acceptance Criteria**: Highlights exact violating lines.
  - **Microtest**: `gitHubChecksPayloadFormatting()`

- [ ] **Task 4.8: OWASP Security & Credential Gate Plugin**
  - **Target File**: `Sources/Gates/SecurityGate.swift`
  - **Description**: Scan diffs for hardcoded API keys, private certs, SQL injection.
  - **Acceptance Criteria**: Rejects commits with private keys or unsanitized inputs.
  - **Microtest**: `securityGateCredentialLeakDetection()`

- [ ] **Task 4.9: OpenTelemetry OTLP Export Pipeline**
  - **Target File**: `Sources/AdventurersCore/TelemetryExporter.swift`
  - **Description**: Export telemetry via OpenTelemetry OTLP protocol.
  - **Acceptance Criteria**: Traces, metrics, logs exported to configurable endpoint.
  - **Microtest**: `telemetryExporterOTLPFormat()`

- [ ] **Task 4.10: Phase 4 Microtest Test Suite Expansion**
  - **Target File**: `Tests/AdventurersCoreTests/Phase4Microtests.swift`

---

## Phase 5: Autonomous Self-Modification & Evaluation Matrix (`v2.1 – v2.5`)

- [ ] **Task 5.1: Immutable Sandbox Self-Hosting Mode**
  - **Target File**: `Sources/AdventurersCore/SelfHostingEngine.swift`
  - **Description**: Adventurers refactors its own code under strict sandboxing and test gates.
  - **Acceptance Criteria**: Code fenced to workspace, auto-revert on `swift test` failure.
  - **Microtest**: `selfHostingEngineSafetyFencing()`

- [ ] **Task 5.2: SWE-bench Verified Dataset Evaluator**
  - **Target File**: `Sources/Eval/SWEBenchRunner.swift`
  - **Description**: Automated SWE-bench Verified benchmark runner.
  - **Acceptance Criteria**: Loads tasks, executes agent runs, tests patches, outputs resolve rate.
  - **Microtest**: `sweBenchDatasetLoadingAndEvaluation()`

- [ ] **Task 5.3: HumanEval Benchmark Runner**
  - **Target File**: `Sources/Eval/HumanEvalRunner.swift`
  - **Description**: In-harness HumanEval code generation benchmarks.
  - **Acceptance Criteria**: pass@1 and pass@5 metrics across configured models.
  - **Microtest**: `humanEvalPassAtOneComputation()`

- [ ] **Task 5.4: Multi-Model Evaluation Matrix UI**
  - **Target File**: `Sources/GUI/EvalMatrixView.swift`
  - **Description**: Side-by-side comparison matrix with resolve rates, TPS, TTFT, cost.
  - **Acceptance Criteria**: Interactive sorting, CSV/JSON export, bar charts.
  - **Microtest**: `evalMatrixDataAggregation()`

- [ ] **Task 5.5: Apple Silicon Hardware Telemetry Monitor**
  - **Target File**: `Sources/AdventurersCore/HardwareTelemetry.swift`
  - **Description**: Query IOKit metrics: Neural Engine, Metal GPU, RAM pressure, thermal.
  - **Acceptance Criteria**: Real-time 1.0s telemetry in status bar.
  - **Microtest**: `hardwareTelemetryQueryIOKit()`

- [ ] **Task 5.6: Plugin Marketplace with Git-Based Distribution**
  - **Target File**: `Sources/AdventurersCore/PluginMarketplace.swift`
  - **Description**: Git-based plugin discovery, sync, and installation (Codex-style).
  - **Acceptance Criteria**: Plugin manifest parsing, startup sync, capability negotiation.
  - **Microtest**: `pluginMarketplaceSyncAndDiscovery()`
  - **Codex Reference**: `core-plugins/src/installed_marketplaces.rs`, `startup_sync.rs`

- [ ] **Task 5.7: Autonomous Hotspot Optimizer**
  - **Target File**: `Sources/AdventurersCore/HotspotOptimizer.swift`
  - **Description**: Profile slow algorithms, propose verified optimizations.
  - **Acceptance Criteria**: Analyzes runtime traces, generates optimized PR branches.
  - **Microtest**: `hotspotOptimizerDetection()`

- [ ] **Task 5.8: Phase 5 Microtest Test Suite Expansion**
  - **Target File**: `Tests/AdventurersCoreTests/Phase5Microtests.swift`

---

## Phase 6: Multi-Agent Mesh & Distributed Swarm (`v2.6.0+`)

- [ ] **Task 6.1: Actor-Based Agent Mesh Protocol**
  - **Target File**: `Sources/Mesh/AgentMeshProtocol.swift`
  - **Description**: Distributed actor protocol with message passing and capability negotiation.
  - **Acceptance Criteria**: Type-safe message exchange between Orchestrator, Specialist, Gatekeeper.
  - **Microtest**: `agentMeshMessageRoutingAndDispatch()`

- [ ] **Task 6.2: Peer-to-Peer Unix Domain Socket Bus**
  - **Target File**: `Sources/Mesh/UnixSocketBus.swift`
  - **Description**: High-throughput IPC for external CLI agents.
  - **Acceptance Criteria**: Sub-millisecond latency, backpressure support.
  - **Microtest**: `unixSocketBusThroughputAndBackpressure()`

- [ ] **Task 6.3: CRDT Shared Context Blackboard**
  - **Target File**: `Sources/Mesh/SharedBlackboard.swift`
  - **Description**: Conflict-free replicated data type for concurrent agents.
  - **Acceptance Criteria**: Causal consistency, no race conditions.
  - **Microtest**: `sharedBlackboardCrdtConcurrentUpdates()`

- [ ] **Task 6.4: Live Swarm Network Topology Graph UI**
  - **Target File**: `Sources/GUI/SwarmTopologyView.swift`
  - **Description**: Interactive node graph visualizing active agents and gate statuses.
  - **Acceptance Criteria**: Animated nodes, panning, zooming, drill-down.
  - **Microtest**: `swarmTopologyGraphStateBinding()`

- [ ] **Task 6.5: Phase 6 Microtest Test Suite Expansion**
  - **Target File**: `Tests/AdventurersCoreTests/Phase6Microtests.swift`

---

## Microtest Suite Matrix

| Test Category | Suite File | Status |
|---|---|---|
| **Task Contract** | `AdventurersCoreTests.swift` | ✅ 100% |
| **State Engine FSM** | `AdventurersCoreTests.swift` | ✅ 100% |
| **FailChain Feedback** | `AdventurersCoreTests.swift` | ✅ 100% |
| **6-Gate Certification** | `AdventurersCoreTests.swift` | ✅ 100% |
| **Darwin Sandbox** | `AdventurersCoreTests.swift` | ✅ 100% |
| **Diff Engine** | `AdventurersCoreTests.swift` | ✅ 100% |
| **Trajectory Compressor** | `AdventurersCoreTests.swift` | ✅ 100% |
| **Model Pricing & TPS** | `AdventurersCoreTests.swift` | ✅ 100% |
| **Meta-Harness Registry** | `AdventurersCoreTests.swift` | ✅ 100% |
| **Phase 2: Exec Policy** | `Phase2Microtests.swift` | 🔲 Pending |
| **Phase 2: Tool Approval** | `Phase2Microtests.swift` | 🔲 Pending |
| **Phase 2: Network Gate** | `Phase2Microtests.swift` | 🔲 Pending |
| **Phase 2: State Store** | `Phase2Microtests.swift` | 🔲 Pending |
| **Phase 2: Context Compactor** | `Phase2Microtests.swift` | 🔲 Pending |
| **Phase 2: Config Stack** | `Phase2Microtests.swift` | 🔲 Pending |
| **Phase 2: Dangerous Commands** | `Phase2Microtests.swift` | 🔲 Pending |

**Total Active Microtests**: **20/20 Passed (0.002s)** on macOS Apple Silicon.

---

## Key Design Patterns

| Pattern | Description | Codex Equivalent |
|---|---|---|
| **The Model Proposes, The Harness Certifies** | LLM never decides completion. Deterministic gates certify. | `evaluate_gates` |
| **Rule-Based Exec Policy** | Granular allow/deny/escalate rules per command pattern. | `codex_execpolicy` |
| **Granular Tool Approval** | Per-tool, per-session approval with escalation. | `ExecApprovalRequestEvent` |
| **Network Permission Gate** | Protocol-level network filtering. | `network_policy_decision` |
| **Deterministic 6-Gate Pipeline** | Syntax → Repeat → Compilation → Diff → Memory → Objective | Custom gates |
| **Darwin Seatbelt Sandboxing** | Kernel-enforced read/write isolation. | `codex_sandbox` |
| **SQLite State Persistence** | Structured thread state and rollout storage. | `state_db` + `rollout` |
| **Context Compaction v2** | Anchor-preserving history compaction. | `compact_remote_v2` |
| **Layered Config System** | 5-layer config precedence stack. | `codex_config` |
| **Multi-Agent Meta-Dispatch** | External sub-agent CLI execution. | `spawn_agent` / `send_input` |
| **Sliding Window TPS Telemetry** | Rolling token velocity and cost metering. | `codex.turn.*` |
| **Escalating FailChain Feedback** | Progressive sternness on repeated failures. | Guardian review |
| **Contract-Based Budget** | Immutable `TaskContract` with turn/token limits. | `codex_turn_id` |
| **In-App GitHub Auto-Updates** | Continuous release monitoring and 1-click install. | Sparkle updater |
| **APFS Snapshot Rollbacks** | Zero-cost instant workspace snapshots. | N/A (Adventurers advantage) |
| **OpenTelemetry Export** | OTLP-compatible telemetry pipeline. | `otel_init` |
| **Plugin Marketplace** | Git-based plugin distribution and sync. | `core-plugins` |
