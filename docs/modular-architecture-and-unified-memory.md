# Adventurers Harness — Modular Architecture & Unified Cognitive Memory System

## 1. Executive Summary & Philosophy

Adventurers Harness is engineered as a high-performance, modular system written in Swift 6. It serves two distinct roles:
1. **Multi-Binary Autonomous Agent Harness**: Provides deterministic execution, gate certification, and safety sandboxing for AI coding agents.
2. **Unified Biomimetic Memory Engine for all Coding CLIs**: A native Swift zero-dependency memory substrate absorbing all features of Hindsight (World Facts, Experience Facts, Observations, and Mental Models) and exposing standard MCP (Model Context Protocol) and CLI endpoints.

---

## 2. Multi-Binary Split Architecture

Rather than coupling the entire harness into a single monolithic GUI executable, the codebase is split into modular binaries and targets:

```
                               ┌─────────────────────────┐
                               │     AdventurersCore     │  (Library)
                               │  - AgentLoop & Gates    │
                               │  - Needle Fast-Path     │
                               │  - Biomimetic Memory    │
                               │  - VectorStore & SIMD   │
                               │  - SourceKit-LSP Client │
                               └────────────┬────────────┘
                     ┌──────────────────────┼──────────────────────┐
                     │                      │                      │
                     ▼                      ▼                      ▼
           ┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐
           │   Adventurers    │   │   adventurers    │   │ adventurers-mcp  │
           │  (SwiftUI GUI)   │   │  (Headless CLI)  │   │  (MCP & Memory)  │
           └──────────────────┘   └──────────────────┘   └──────────────────┘
```

### Binary Overview

| Binary | Target / Entry | Purpose | Primary Use Cases |
| :--- | :--- | :--- | :--- |
| **`Adventurers`** | `Sources/GUI/` | Native macOS SwiftUI application | Interactive pair programming, Visual Diff & 3-Way Merge, Terminal Streaming, Live Memory Tab (`⌘5`). |
| **`adventurers`** | `Sources/CLI/` | Headless CLI agent runner & certifier | Terminal workflows, automated CI/CD pipeline runs (`adventurers check-gates`), dogfooding loops. |
| **`adventurers-mcp`** | `Sources/UnifiedMemoryMCPServer/` | Zero-dependency MCP & Memory CLI | Headless cognitive memory server and CLI tool for AGY (`antigravity-cli`), Claude Code, Cursor, OpenCode, and Codex. |

---

## 3. Unified Cognitive Memory Architecture (Native Swift Hindsight)

The memory system replaces external Docker/Python daemons with pure Swift 6 actor-isolated engines operating directly on disk at `~/.adventurers/knowledge/`.

### 3.1 Cognitive Hierarchy

1. **World Facts**: Objective external invariants, language rules, API specs, and strict concurrency contracts.
2. **Experience Facts**: Episodic memory traces of agent turns, executed shell commands, tool results, and outcomes.
3. **Observations**: Inductively-derived patterns clustered across multiple session experiences.
4. **Mental Models**: Living, curated knowledge pages (Architecture, Conventions, Initiatives) that guide high-level agent planning.

### 3.2 The Cognitive Loop

- **Retain**: Ingests new records, automatically generating Apple Accelerate `vDSP` normalized dense embedding vectors.
- **Recall**: Hybrid lexical token matching + SIMD Cosine Similarity vector search across memory records in <2ms.
- **Reflect**: Synthesizes cross-record reasoning traces to explain *why* architectural decisions or constraints exist.

---

## 4. MCP & CLI Memory Commands

The unified memory system can be accessed both as an MCP server over JSON-RPC stdio and as a direct terminal CLI:

```bash
# Start MCP JSON-RPC Server (for IDEs / CLIs)
adventurers-mcp

# List all stored mental models & knowledge pages
adventurers-mcp list

# Read a specific knowledge page
adventurers-mcp read swift6-concurrency

# Search memory using hybrid semantic search
adventurers-mcp search "diff safety and rollback"

# Perform cognitive memory reflection
adventurers-mcp reflect "how are commands routed locally?"

# Ingest new durable notes or decisions
adventurers-mcp ingest "Retry Policy" "4xx errors are permanent; 5xx/429 are transient."

# Check memory health and sync status
adventurers-mcp status
```

---

## 5. Ongoing Roadmap & Execution Plan

### Phase 2: In-Memory LSP & Neural Acceleration (`v1.2 – v1.3`) — *COMPLETE*
- [x] Native SourceKit-LSP Client (`Sources/AdventurersCore/SourceKitLSPClient.swift`)
- [x] Sub-50ms LSP Compilation Preflight Gate (`Sources/AdventurersCore/LSPCompilationGate.swift`)
- [x] Polyglot LSP Manager for Swift, Rust, Zig, Python (`Sources/AdventurersCore/MultiLanguageLSPManager.swift`)
- [x] SIMD Cosine Vector Store (`Sources/AdventurersCore/VectorStore.swift`)
- [x] Structural AST Chunker (`Sources/AdventurersCore/ASTChunker.swift`)
- [x] Apple Accelerate Embeddings Engine (`Sources/AdventurersCore/LocalEmbeddingEngine.swift`)
- [x] Autonomous Dogfooding Loop (`Sources/AdventurersCore/DogfoodManager.swift`)
- [x] Biomimetic Cognitive Memory Engine (`Sources/AdventurersCore/BiomimeticMemory.swift`)
- [x] Multi-Binary Split Architecture (`Adventurers`, `adventurers`, `adventurers-mcp`)

### Phase 3: WebAssembly Gate Plugins, Team Policies & 3-Way Diff (`v1.4 – v1.6`)
- [ ] Task 3.1: Wasmtime WebAssembly Gate Runner (`Sources/AdventurersCore/WasmGateRunner.swift`)
- [ ] Task 3.2: Standard Gate WASI Interface Protocol (`Sources/AdventurersCore/WasiGateInterface.swift`)
- [ ] Task 3.3: Repository `.adventurers/gates.json` Policy Parser (`Sources/AdventurersCore/GatePolicyLoader.swift`)
- [ ] Task 3.4: Visual 3-Way Merge Conflict Resolver Canvas (`Sources/GUI/DiffMergeView.swift`)
- [ ] Task 3.5: Tree-Sitter Semantic AST Diff Visualizer (`Sources/GUI/SemanticDiff.swift`)
- [ ] Task 3.6: APFS Copy-on-Write Atomic Snapshot Rollbacks (`Sources/AdventurersCore/APFSSnapshot.swift`)
- [ ] Task 3.7: Team Gate Attestation CLI (`adventurers check-gates` CI integration)
- [ ] Task 3.8: GitHub PR Checks API Annotations Reporter (`Sources/CLI/GitHubChecksReporter.swift`)
- [ ] Task 3.9: OWASP Security & Credential Gate Plugin (`Sources/Gates/SecurityGate.swift`)

### Phase 4: Autonomous Harness Self-Modification & Benchmark Suite (`v2.0.0+`)
- [ ] Task 4.1: Immutable Sandbox Self-Hosting Mode
- [ ] Task 4.2: SWE-bench Verified Dataset Evaluator
- [ ] Task 4.3: HumanEval Benchmark Runner
- [ ] Task 4.4: Multi-Model Evaluation Matrix UI Canvas
- [ ] Task 4.5: Apple Silicon Hardware Telemetry Monitor (IOKit NE/Metal/RAM)
- [ ] Task 4.6: Autonomous Hotspot Optimizer
