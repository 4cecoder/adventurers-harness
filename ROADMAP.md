# Adventurers Harness — Architectural Roadmap & Microtasks

> **North Star**: Build the most dependable, deterministic, and high-velocity macOS-native coding agent harness on Apple Silicon.  
> **Core Principle**: *The model proposes. The harness certifies.*

---

## 🗺️ High-Level Milestone Architecture

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
│  Phase 2: Local Intelligence, PTY & Language Server Protocol (v1.1 – v1.3)  │
│  • Native POSIX PTY Pseudo-Terminal with Full ANSI/VT100 Emulation          │
│  • SourceKit-LSP & Multi-Language Server Protocol Integration                │
│  • Local Vector Corpus Embedding & Fast Codebase Search                      │
│  • Autonomous Self-Development Dogfooding Loop                              │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Phase 3: Extensible Gate Plugins, Team Policies & 3-Way Diff (v1.4 – v1.6) │
│  • WebAssembly (Wasmtime) & Swift Dynamic Gate Plugin Architecture          │
│  • Visual 3-Way Diff Resolution & APFS Snapshot Rollbacks                   │
│  • Team Gate Policies (.adventurers/gates.json) & CI Attestation Sync       │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Phase 4: Autonomous Harness Self-Modification & Eval Matrix (v2.0.0+)      │
│  • Self-Hosting Optimization under Immutable Verification Gates             │
│  • Live SWE-bench Verified & HumanEval GUI Evaluator                        │
│  • Hardware Telemetry (Apple Neural Engine, Metal GPU, Thermal State)       │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Phase 5: Multi-Agent Mesh & Distributed Swarm (v2.5.0+)                   │
│  • Actor-Based Agent Mesh Protocol with P2P Unix Sockets                    │
│  • Live Swarm Network Topology Graph & Work-Stealing Task Queue             │
│  • Multi-Machine Apple Silicon Distributed Cluster Execution                │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 📋 Microtasks Breakdown

### Phase 1: Foundation & Core Engine (`v1.0.0` — ✅ Completed & Verified)

- [x] **Task 1.1: Three-Panel SwiftUI Desktop Architecture**
  - **Files**: `Sources/GUI/AdventurersApp.swift`, `Sources/GUI/ThreadListView.swift`, `Sources/GUI/ThreadView.swift`
  - **Acceptance Criteria**: Fluid 3-panel layout (Threads Sidebar, Chat/Diff Canvas, Inspector Panel), Obsidian Glass design system, 60 FPS streaming.
  - **Microtests**: Passed `stateEngineFullLifecycle` and UI state bindings.

- [x] **Task 1.2: 6-Gate Deterministic Certification Pipeline**
  - **Files**: `Sources/AdventurersCore/Gates.swift`, `Sources/AdventurersCore/Protocols.swift`
  - **Gates Implemented**:
    1. `SyntaxGate`: Bracket, parenthesis, and square bracket balancing with markdown fence extraction.
    2. `RepeatGate`: Loop and repetitive duplicate submission detection via cryptographic MD5 hashing.
    3. `CompilationGate`: Non-destructive swift type-checking and build verification.
    4. `DiffGate`: High-risk command inspection (`rm -rf`, `sudo`, `dd`, `git push -f`) and protected file fencing (`.env`, `~/.ssh/`, `/etc/shadow`).
    5. `MemoryGate`: POSIX `getrusage` resident set size verification bounding task memory.
    6. `ObjectiveGate`: Immutable contract prompt keyword and budget matching.
  - **Microtests**: Passed `syntaxGateBoundaryCases`, `repeatGateCycleDetection`, `diffGateRiskDetection`, `memoryGateEvaluation`, `objectiveGateEvaluation`.

- [x] **Task 1.3: Darwin Seatbelt Kernel Sandboxing**
  - **Files**: `Sources/AdventurersCore/DarwinSandbox.swift`
  - **Acceptance Criteria**: Kernel-enforced SBPL sandbox profile generation for read-only vs workspace-write modes.
  - **Microtests**: Passed `darwinSandboxPathAccess` boundary tests.

- [x] **Task 1.4: Pure Swift Streaming Patch & Diff Engine**
  - **Files**: `Sources/AdventurersCore/DiffEngine.swift`
  - **Acceptance Criteria**: Unified diff parser, context-aware preflight conflict detection, and atomic patch applier.
  - **Microtests**: Passed `diffEngineMultiHunk` and `diffEngineCorruptedContext`.

- [x] **Task 1.5: Sliding Window TPS Telemetry & Multi-Model Cost Ledger**
  - **Files**: `Sources/AdventurersCore/MeteringTelemetry.swift`, `Sources/GUI/WorkbenchStatusBar.swift`
  - **Acceptance Criteria**: 1.2s rolling token velocity meter, TTFT latency tracking, context headroom gauges, and multi-tier pricing registry.
  - **Microtests**: Passed `modelPricingMultiTier` and `turnMetricsAccounting`.

- [x] **Task 1.6: Multi-Agent Meta-Harness Dispatch**
  - **Files**: `Sources/AdventurersCore/MetaHarness.swift`, `Sources/GUI/SettingsView.swift`
  - **Acceptance Criteria**: Process isolation, custom CLI mappings, and environment variable isolation for `agy` (Google Antigravity), `claude` (Anthropic Claude Code), `codex`, `hermes`, `opencode`, `dsh`, `pi`, `smallctl`.
  - **Microtests**: Passed `metaHarnessRegistryDiscovery`.

- [x] **Task 1.7: In-App GitHub Releases Auto-Updater & Homebrew Packaging**
  - **Files**: `Sources/GUI/AppUpdateManager.swift`, `Formula/adventurers.rb`, `Casks/adventurers.rb`, `scripts/package_app.sh`, `.github/workflows/`
  - **Acceptance Criteria**: Semver release comparison against GitHub Releases API, 1-click installer mounting, Homebrew formula tap, and GitHub Pages deployment.

---

### Phase 2: Local Intelligence, PTY & Language Server Protocol (`v1.1 – v1.3`)

- [x] **Task 2.1: POSIX PTY Pseudo-Terminal Subsystem**
  - **Target File**: `Sources/AdventurersCore/TerminalPTY.swift`
  - **Description**: Native macOS Pseudo-Terminal (`openpty`/`forkpty` Darwin system calls) with bidirectional non-blocking streams, `TIOCSWINSZ` dynamic window resizing, and child process lifecycle management.
  - **Microtest**: Passed `ptyAllocationAndResize()`.

- [x] **Task 2.2: Streamed ANSI / VT100 Escape Sequence Parser**
  - **Target File**: `Sources/AdventurersCore/TerminalANSIParser.swift`, `Sources/GUI/TerminalANSIView.swift`
  - **Description**: Fast tokenizing state machine parsing ANSI standard 16 colors, 256-color palette, 24-bit TrueColor RGB, text styles (bold, dim, italic, underline, inverse), and ANSI stripping.
  - **Microtest**: Passed `parseStandardANSIColors()`, `parseExtendedANSIColors()`, `stripANSIEscapeSequences()`.

- [x] **Task 2.3: Bi-Directional Interactive Stdin Controller**
  - **Target File**: `Sources/AdventurersCore/TerminalStdinController.swift`
  - **Description**: Forward user keystrokes (Ctrl+C, Ctrl+D, Ctrl+Z, arrow keys, Tab auto-complete) into running sub-processes.
  - **Acceptance Criteria**: Interactive tools like `vim`, `htop`, `git rebase -i`, and CLI prompts respond interactively in the terminal panel.
  - **Microtest**: Passed `testTerminalKeyEncoding()` and `testStdinHistoryNavigation()`.

- [x] **Task 2.4: JSON-RPC 2.0 Asynchronous Transport Engine**
  - **Target File**: `Sources/AdventurersCore/JSONRPCTransport.swift`
  - **Description**: Pure Swift async/await JSON-RPC 2.0 framed transport with `Content-Length` headers for Language Server Protocol communication.
  - **Acceptance Criteria**: Serializes/deserializes LSP requests, notifications, and responses with error code handling.
  - **Microtest**: Passed `testJSONRPCFramer()`, `testChunkedJSONRPCFrames()`, and `testJSONRPCSerialization()`.

- [ ] **Task 2.5: Native SourceKit-LSP Client Connection**
  - **Target File**: `Sources/LSP/SourceKitLSPClient.swift`
  - **Description**: Launches and manages background `/usr/bin/sourcekit-lsp` server instance bound to the active workspace.
  - **Acceptance Criteria**: Sends `initialize`, `textDocument/didOpen`, `textDocument/didChange`, and receives diagnostics in real-time.
  - **Microtest**: `sourceKitLSPInitializeAndDiagnostics()`

- [ ] **Task 2.6: Real-Time In-Memory LSP CompilationGate**
  - **Target File**: `Sources/AdventurersCore/LSPCompilationGate.swift`
  - **Description**: Preflight proposed Swift changes against SourceKit-LSP diagnostics without touching disk or running full `swift build`.
  - **Acceptance Criteria**: Rejects syntax/type errors in under 50ms before writing changes.
  - **Microtest**: `lspCompilationGateSubSecondPreflight()`

- [ ] **Task 2.7: Multi-Language LSP Support Matrix (Rust, Zig, Python)**
  - **Target File**: `Sources/LSP/MultiLanguageLSPManager.swift`
  - **Description**: Auto-detects project language and connects to `rust-analyzer` (Rust), `zls` (Zig), or `pyright` (Python) if available.
  - **Acceptance Criteria**: Polyglot projects receive compiler diagnostics across all supported languages.
  - **Microtest**: `multiLanguageLSPDiscoveryAndBinding()`

- [ ] **Task 2.8: SQLite Vector Embedding Store (`sqlite-vec`)**
  - **Target File**: `Sources/Corpus/VectorStore.swift`
  - **Description**: Embedded SQLite vector storage with Cosine similarity indexing for local project codebase embeddings.
  - **Acceptance Criteria**: Stores 1536-dim or 384-dim embeddings with sub-5ms nearest-neighbor queries across 10,000 code chunks.
  - **Microtest**: `vectorStoreInsertionAndCosineQuery()`

- [ ] **Task 2.9: Semantic AST Code Chunker**
  - **Target File**: `Sources/Corpus/ASTChunker.swift`
  - **Description**: Splits source code files along structural AST boundaries (classes, structs, functions, protocols) rather than arbitrary line counts.
  - **Acceptance Criteria**: Preserves complete function signatures and docstrings in every chunk.
  - **Microtest**: `astChunkerPreservesSignaturesAndContext()`

- [ ] **Task 2.10: Apple Accelerate BNNS Local Embeddings Engine**
  - **Target File**: `Sources/Corpus/LocalEmbeddingEngine.swift`
  - **Description**: Runs lightweight embedding models directly on Apple Silicon Neural Engine / Metal via Accelerate framework.
  - **Acceptance Criteria**: Generates embeddings offline at >500 chunks/sec with 0 network latency.
  - **Microtest**: `localEmbeddingGenerationSpeedAndAccuracy()`

- [ ] **Task 2.11: Self-Hosted Dogfooding Loop (`/dogfood`)**
  - **Target File**: `Sources/GUI/DogfoodManager.swift`
  - **Description**: Automated one-click workflow where Adventurers Harness uses its own tools and gates to inspect, build, test, and package its own repository.
  - **Acceptance Criteria**: Self-dev quick chips trigger complete preflight certification, build, and test runs with detailed progress reports.
  - **Microtest**: `dogfoodPipelineExecutionAndSelfCheck()`

- [ ] **Task 2.12: Phase 2 Microtest Test Suite Expansion**
  - **Target File**: `Tests/AdventurersCoreTests/Phase2Microtests.swift`
  - **Description**: Comprehensive unit test suite covering Tasks 2.1 through 2.11.

---

### Phase 3: WebAssembly Gate Plugins, Team Policies & 3-Way Diff (`v1.4 – v1.6`)

- [ ] **Task 3.1: Wasmtime WebAssembly Gate Runner**
  - **Target File**: `Sources/AdventurersCore/WasmGateRunner.swift`
  - **Description**: Embeds lightweight WebAssembly runtime (Wasmtime) to execute user-defined custom gate binaries in sandbox.
  - **Acceptance Criteria**: Executes WASM bytecode with memory quotas (<64MB) and instruction timeouts (<500ms).
  - **Microtest**: `wasmGateExecutionAndTimeoutBounding()`

- [ ] **Task 3.2: Standard Gate WASI Interface Protocol**
  - **Target File**: `Sources/AdventurersCore/WasiGateInterface.swift`
  - **Description**: Defines standardized C/WASI ABI for custom gates written in Rust, Go, TypeScript, or Swift.
  - **Acceptance Criteria**: Passing input JSON via stdin and reading structured `GateResult` JSON from stdout.
  - **Microtest**: `wasiGateInterfaceJsonSerialization()`

- [ ] **Task 3.3: Repository `.adventurers/gates.json` Policy Parser**
  - **Target File**: `Sources/AdventurersCore/GatePolicyLoader.swift`
  - **Description**: Loads declarative gate configuration committed in user repositories, allowing per-repo custom gate thresholds.
  - **Acceptance Criteria**: Parses required gates, timeouts, memory limits, and custom WASM gate paths.
  - **Microtest**: `gatePolicyJsonSchemaValidation()`

- [ ] **Task 3.4: Visual 3-Way Merge Conflict Resolver Canvas**
  - **Target File**: `Sources/GUI/DiffMergeView.swift`
  - **Description**: Interactive side-by-side 3-pane merge UI (Ours / Base / Theirs) for reviewing conflicting agent edits.
  - **Acceptance Criteria**: Visual hunk selection, manual editing, and 1-click conflict acceptance.
  - **Microtest**: `threeWayMergeConflictDetection()`

- [ ] **Task 3.5: Tree-Sitter Semantic AST Diff Visualizer**
  - **Target File**: `Sources/GUI/SemanticDiff.swift`
  - **Description**: Uses Tree-sitter AST parsing to highlight renamed variables, moved functions, and altered type signatures rather than raw line diffs.
  - **Acceptance Criteria**: Distinguishes structural code changes from superficial whitespace or formatting changes.
  - **Microtest**: `semanticDiffAstAlterationDetection()`

- [ ] **Task 3.6: APFS Copy-on-Write Atomic Snapshot Rollbacks**
  - **Target File**: `Sources/AdventurersCore/APFSSnapshot.swift`
  - **Description**: Leverages macOS APFS native clone (`clonefile()`) for zero-cost instant workspace snapshotting before executing high-risk agent commands.
  - **Acceptance Criteria**: Instant sub-10ms snapshot creation and atomic rollback on gate rejection.
  - **Microtest**: `apfsSnapshotCreationAndRollback()`

- [ ] **Task 3.7: Team Gate Attestation CLI (`adventurers check-gates`)**
  - **Target File**: `Sources/CLI/GateCheckCommand.swift`
  - **Description**: Command-line tool to run the identical 6-gate deterministic pipeline inside GitHub Actions or GitLab CI.
  - **Acceptance Criteria**: Exits 0 on clean certification, non-zero with structured SARIF output on failures.
  - **Microtest**: `cliGateCheckCommandExecution()`

- [ ] **Task 3.8: GitHub PR Checks API Annotations Reporter**
  - **Target File**: `Sources/CLI/GitHubChecksReporter.swift`
  - **Description**: Post detailed gate evaluation results as rich line annotations on GitHub Pull Requests.
  - **Acceptance Criteria**: Highlights exact lines violating syntax, repeat, or diff gates in GitHub PR UI.
  - **Microtest**: `gitHubChecksPayloadFormatting()`

- [ ] **Task 3.9: OWASP Security & Credential Gate Plugin**
  - **Target File**: `Sources/Gates/SecurityGate.swift`
  - **Description**: Built-in security gate scanning proposed diffs for hardcoded API keys, private certificates, SQL injection vulnerabilities, and path traversal vectors.
  - **Acceptance Criteria**: Rejects commits containing private key patterns or unsanitized shell inputs.
  - **Microtest**: `securityGateCredentialLeakDetection()`

- [ ] **Task 3.10: Phase 3 Microtest Test Suite Expansion**
  - **Target File**: `Tests/AdventurersCoreTests/Phase3Microtests.swift`
  - **Description**: Comprehensive unit test suite covering Tasks 3.1 through 3.9.

---

### Phase 4: Autonomous Harness Self-Modification & Evaluation Matrix (`v2.0.0+`)

- [ ] **Task 4.1: Immutable Sandbox Self-Hosting Mode**
  - **Target File**: `Sources/AdventurersCore/SelfHostingEngine.swift`
  - **Description**: Enables Adventurers Harness to autonomously refactor and optimize its own codebase under strict immutable sandboxing and test gates.
  - **Acceptance Criteria**: Code modification is fenced to workspace, and automatically reverted if `swift test` fails.
  - **Microtest**: `selfHostingEngineSafetyFencing()`

- [ ] **Task 4.2: SWE-bench Verified Dataset Evaluator**
  - **Target File**: `Sources/Eval/SWEBenchRunner.swift`
  - **Description**: Automated benchmark runner for SWE-bench Verified problem instances directly inside the macOS harness.
  - **Acceptance Criteria**: Loads benchmark tasks, executes agent runs, tests patch outputs, and outputs resolve rate percentage.
  - **Microtest**: `sweBenchDatasetLoadingAndEvaluation()`

- [ ] **Task 4.3: HumanEval Benchmark Runner**
  - **Target File**: `Sources/Eval/HumanEvalRunner.swift`
  - **Description**: In-harness test harness for HumanEval code generation benchmarks.
  - **Acceptance Criteria**: Evaluates pass@1 and pass@5 metrics across configured models.
  - **Microtest**: `humanEvalPassAtOneComputation()`

- [ ] **Task 4.4: Multi-Model Evaluation Matrix UI Canvas**
  - **Target File**: `Sources/GUI/EvalMatrixView.swift`
  - **Description**: Rich comparison matrix in GUI displaying side-by-side resolve rates, token velocity (TPS), TTFT, and cost per task across all models.
  - **Acceptance Criteria**: Interactive sorting, CSV/JSON export, and live model comparison bar charts.
  - **Microtest**: `evalMatrixDataAggregation()`

- [ ] **Task 4.5: Apple Silicon Hardware Telemetry Monitor**
  - **Target File**: `Sources/AdventurersCore/HardwareTelemetry.swift`
  - **Description**: Queries Apple Silicon IOKit metrics: Neural Engine utilization, Metal GPU load, RAM pressure, and thermal throttling state.
  - **Acceptance Criteria**: Real-time 1.0s telemetry stream rendered in status bar cluster.
  - **Microtest**: `hardwareTelemetryQueryIOKit()`

- [ ] **Task 4.6: Autonomous Hotspot Optimizer**
  - **Target File**: `Sources/AdventurersCore/HotspotOptimizer.swift`
  - **Description**: Profiling agent identifying slow algorithms or high-memory routines in user code and generating optimized PR branches.
  - **Acceptance Criteria**: Analyzes runtime traces and proposes verified algorithmic improvements.
  - **Microtest**: `hotspotOptimizerDetection()`

---

### Phase 5: Multi-Agent Mesh & Distributed Swarm (`v2.5.0+`)

- [ ] **Task 5.1: Actor-Based Agent Mesh Protocol (AMP)**
  - **Target File**: `Sources/Mesh/AgentMeshProtocol.swift`
  - **Description**: Distributed actor protocol enabling multi-agent coordination with message passing and capability negotiation.
  - **Acceptance Criteria**: Type-safe message exchange between Orchestrator, Specialist, and Gatekeeper actors.
  - **Microtest**: `agentMeshMessageRoutingAndDispatch()`

- [ ] **Task 5.2: Peer-to-Peer Local Unix Domain Socket Bus**
  - **Target File**: `Sources/Mesh/UnixSocketBus.swift`
  - **Description**: High-throughput IPC bus for communicating with external CLI agents and helper processes via Unix domain sockets.
  - **Acceptance Criteria**: Sub-millisecond latency IPC message delivery with backpressure support.
  - **Microtest**: `unixSocketBusThroughputAndBackpressure()`

- [ ] **Task 5.3: CRDT Shared Context Blackboard**
  - **Target File**: `Sources/Mesh/SharedBlackboard.swift`
  - **Description**: Conflict-free replicated data type (CRDT) memory blackboard shared across concurrent agents working on distinct files.
  - **Acceptance Criteria**: Seamless causal consistency without race conditions or lost updates.
  - **Microtest**: `sharedBlackboardCrdtConcurrentUpdates()`

- [ ] **Task 5.4: Live Swarm Network Topology Graph UI**
  - **Target File**: `Sources/GUI/SwarmTopologyView.swift`
  - **Description**: Interactive node graph in SwiftUI visualizing active agents, sub-tasks, message channels, and gate verification statuses.
  - **Acceptance Criteria**: Animated node graph with panning, zooming, and agent drill-down inspection.
  - **Microtest**: `swarmTopologyGraphStateBinding()`

---

## 🧪 Microtest Suite Matrix

| Test Category | Suite File | Microtests Included | Status |
|---|---|---|---|
| **Task Contract** | `AdventurersCoreTests.swift` | `taskContractInitialValues`, `taskContractBudgetExhaustion`, `taskContractTokenAccounting` | ✅ Passed (100%) |
| **State Engine FSM** | `AdventurersCoreTests.swift` | `stateEngineFullLifecycle`, `stateEngineIllegalTransitions`, `stateEngineRejectionLoop` | ✅ Passed (100%) |
| **FailChain Feedback** | `AdventurersCoreTests.swift` | `failChainMultiGateEscalation`, `failChainMessageFormatting` | ✅ Passed (100%) |
| **6-Gate Certification** | `AdventurersCoreTests.swift` | `syntaxGateBoundaryCases`, `repeatGateCycleDetection`, `diffGateRiskDetection`, `memoryGateEvaluation`, `objectiveGateEvaluation` | ✅ Passed (100%) |
| **Darwin Sandbox** | `AdventurersCoreTests.swift` | `darwinSandboxPathAccess` | ✅ Passed (100%) |
| **Diff Engine** | `AdventurersCoreTests.swift` | `diffEngineMultiHunk`, `diffEngineCorruptedContext` | ✅ Passed (100%) |
| **Trajectory Compressor**| `AdventurersCoreTests.swift` | `trajectoryCompressorAnchorPreservation` | ✅ Passed (100%) |
| **Model Pricing & TPS** | `AdventurersCoreTests.swift` | `modelPricingMultiTier`, `turnMetricsAccounting` | ✅ Passed (100%) |
| **Meta-Harness Registry**| `AdventurersCoreTests.swift` | `metaHarnessRegistryDiscovery` | ✅ Passed (100%) |

**Total Active Microtests**: **20/20 Passed (0.002s)** on macOS Apple Silicon.
