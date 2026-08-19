# Codex Architecture — Deep Reverse Engineering Reference

> Comprehensive analysis of OpenAI's Codex binary and source code, derived from IDA Pro disassembly, string extraction, and codex-rs source inspection. Used to inform Adventurers Harness bulletproof architecture.

---

## 1. Binary Overview

| Property | Value |
|----------|-------|
| **Binary** | `codex-aarch64-apple-darwin` (Mach-O 64-bit ARM64) |
| **Size** | 212 MB |
| **Language** | Rust (codex-rs workspace) |
| **Location** | `/Applications/ChatGPT.app/Contents/Resources/codex` |
| **Total Strings Extracted** | 2,720 |
| **Rust Namespaces** | `codex_core`, `codex_agent`, `codex_ipc`, `codex_sandbox`, `codex_mcp_server`, `codex_core_plugins`, `codex_features`, `codex_core::guardian` |

### Companion Binaries

| Binary | Size | Role |
|--------|------|------|
| `codex-macos` | — | Native macOS helper (reminders, system bridge) |
| `codex-code-mode-host` | 51 MB | Code execution isolation host (sandboxed) |

---

## 2. High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Electron GUI (ChatGPT.app)                   │
│   asar-extracted/.vite/build/main-*.js                          │
│   Spawns `codex app-server` over stdio/WebSocket                │
└──────────────────────────┬──────────────────────────────────────┘
                           │ JSON-RPC 2.0 (stdio / WebSocket)
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                      codex app-server                            │
│   codex_app_server::mcp_refresh                                  │
│   Session management, MCP tool discovery, thread routing         │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                       codex-core                                 │
│   Agent Loop · Gate Evaluation · Context Management              │
│   Exec Policy · Sandbox · Trajectory Compaction                  │
└──────┬──────────┬───────────┬──────────────┬────────────────────┘
       │          │           │              │
       ▼          ▼           ▼              ▼
   ┌────────┐ ┌────────┐ ┌─────────┐ ┌────────────┐
   │ Tools  │ │ Guard- │ │ Exec-   │ │ Responses  │
   │ (shell,│ │ ian    │ │ Policy  │ │ API Proxy  │
   │ apply, │ │ Review │ │ Engine  │ │ (LLM)     │
   │ grep)  │ │        │ │         │ │            │
   └────────┘ └────────┘ └─────────┘ └────────────┘
```

---

## 3. Agent Loop — The Core FSM

Codex implements a **propose → execute → verify → repair** cycle, functionally identical to Adventurers Harness but with deeper subsystem integration.

### States (from `codex_core::agent`)

```
idle → task_ingested → proposing → validating_syntax → compiling
  → executing_test → verified → idle
      ↓                    ↓
    retrying ←────────────┘
      ↓
    failed → idle
```

### Turn Budgeting
- `codex_turn_id` tracks each LLM round
- Token budget tracked via `codex.turn.token_usage` (cached_input, cache_write_input)
- TTFM (time-to-first-token) measured via `codex.turn.ttfm.duration_ms`
- Context compaction triggers via `responses_compaction_v2` when token limit approached

### Key Differences from Adventurers Harness
| Feature | Codex | Adventurers |
|---------|-------|-------------|
| Agent Loop | Rust async actor with FSM | Swift 6 actor with FSM |
| Turn tracking | `codex_turn_id` + rollout persistence | `AgentOutput.turnIndex` |
| Context compaction | `compact_remote_v2` with anchor preservation | `TrajectoryCompressor` head/tail |
| Multi-agent | Subagent spawning via `spawn_agent` / `send_input` / `resume_agent` | `MetaHarness` subprocess dispatch |

---

## 4. Gate & Certification System

Codex's gates are embedded in the exec policy engine rather than a standalone gate pipeline.

### Execution Policy Engine (`codex_execpolicy`)

The exec policy engine is a **rule-based permission evaluator** that determines what the agent can do:

```
Policy → Rules → Evaluation → Decision (allow/deny/escalate)
```

**Key types:**
- `Policy` — loaded from `.codex/` config or bundled defaults
- `Decision` — `Allow`, `Deny`, `AskForApproval`, `Escalate`
- `Evaluation` — result of matching a command against policy rules
- `RequirementsExecPolicy` — policy with approval requirements

### Three-Tier Sandbox (from `codex_sandbox`)

| Tier | Description | Implementation |
|------|-------------|----------------|
| `read-only` | File read only, no writes | Seatbelt profile `deny default` + `allow file-read*` |
| `workspace-write` | Writes restricted to workspace root | Seatbelt profile with `subpath` write rules |
| `danger-full-access` | Unrestricted system access | Seatbelt profile `allow default` |

### Approval Flow (`codex_core::guardian`)

The Guardian system implements a **review session** pattern:

1. Agent proposes action (tool call, file edit, shell command)
2. Guardian creates `approval_request` with risk assessment
3. User reviews via `RequestPermissionsEvent` / `ExecApprovalRequestEvent`
4. Decision recorded: `approved`, `denied`, `timed_out`
5. For `apply_patch`: separate `ApplyPatchApprovalRequestEvent`

### Dangerous Command Detection (`codex_shell_command`)

Codex maintains a curated list of dangerous command prefixes:
- Shell wrappers: `bash`, `zsh`, `fish`, `sh`, `dash`, `ksh`, `osascript`
- Package runners: `npm run`, `bun run`, `npx`, `cargo`
- System tools: `dd`, `mkfs`, `chmod -R 777`, `rm -rf`
- Network: `curl | sh`, `wget | bash`

---

## 5. Tool Execution System

### Built-in Tools (from string analysis)

| Tool | Source Module | Risk Level |
|------|--------------|------------|
| `shell` / `user_shell` | `codex_shell_command` | execute |
| `apply_patch` | `apply-patch/src/` | write (destructive) |
| `file_edit` | `tools/` | write |
| `grep` / `glob` | `file-search/` | readOnly |
| `web_search` | `web_search.rs` | network |
| `unified_exec` | `unified_exec/` | execute |
| `imagegen` | `ext/` | network |

### Tool Call Events (from string extraction)

```
codex_command_execution_event
codex_file_change_event
codex_mcp_tool_call_event
codex_dynamic_tool_call_event
codex_collab_agent_tool_call_event
```

### Unified Exec (`unified_exec`)
Codex uses a unified execution backend that handles:
- Local shell commands
- Remote exec-server commands
- Sandboxed code execution (via `codex-code-mode-host`)
- Windows sandbox (via `windows-sandbox-rs`)

---

## 6. MCP (Model Context Protocol) Integration

### Architecture

```
codex-mcp → mcp_connection_manager → MCP Tool Registry
                                      ├── Local tools (shell, file, grep)
                                      ├── MCP server tools (external)
                                      └── Dynamic tools (runtime-discovered)
```

### MCP Tool Configuration

From `codex_mcp_server::codex_tool_config`:
- `CodexToolCallSandboxMode` — per-tool sandbox level
- `CodexToolCallApprovalPolicy` — per-tool approval requirement

### MCP Server Management

```
codex mcp add my-tool -- my-command
codex mcp list
```

- OAuth login supported for streamable HTTP servers
- API key piping: `printenv OPENAI_API_KEY | codex ...`
- Tool list change detection via `mcp_tool_exposure`

---

## 7. Session & State Management

### Thread Persistence

Codex persists sessions via:
- **Rollout files** — serialized conversation state
- **State DB** — SQLite-backed session metadata
- **Thread store** — per-thread conversation history

### Key Session Events

```
session_init.thread_persistencesession_init.state_dbsession_init.auth_mcp
codex.thread.startedsession_init.plugin_skill_warmup
session_init.thread_name_lookupsession_init.network_proxy
```

### Context Compaction (`compact_remote_v2`)

When context exceeds token budget:
1. Preserve head anchor (system prompt + task contract)
2. Preserve tail anchor (recent N turns)
3. Compact middle turns into synthetic summary
4. Maintain role alternation validity

---

## 8. Network & Security

### Network Policy

From `network_policy_decision`:
- `allow` / `deny` decisions per network rule
- HTTP/HTTPS connect protocols
- SOCKS5 proxy support (`enable_socks5`, `enable_socks5_udp`)
- Managed network proxy with refresh semaphore

### Authentication Modes

| Mode | Description |
|------|-------------|
| `nativeSubscription` | CLI manages own OAuth/token cache |
| `injectedApiKey` | Environment variable injection |
| `hybrid` | Auto-detect: local session → key fallback |

### Safety Features

- `CODEX_SANDBOX_NETWORK_DISABLED` — disables network in sandbox
- `CODEX_SANDBOX=seatbelt` — set on child processes under Seatbelt
- `CODEX_ESCALATE_SOCKET` — escalation communication channel
- Session flags: `rate_limit_reached`, `workspace_owner_credits_depleted`

---

## 9. Plugin & Marketplace System

### Plugin Architecture (`codex_core_plugins`)

```
plugins/
├── installed_marketplaces.rs   — marketplace source management
├── startup_sync.rs             — plugin synchronization on launch
├── remote.rs                   — remote plugin discovery
└── codex_tool_config.rs        — per-plugin tool configuration
```

### Marketplace Sources

```toml
# .codex/config.toml
[marketplaces]
source = "git+https://github.com/openai/codex-plugins"
```

- Git-based plugin distribution
- Plugin capabilities: `long_description`, `developer_name`, `capabilities`, `website_url`
- Plugin sync on startup via `codex.plugins.startup_sync`

---

## 10. Collaboration & Multi-Agent

### Subagent Protocol

```
spawn_agent → send_input → resume_agent → wait_agent → close_agent
```

- Agent nicknames from `agent_names.txt`
- Agent roles: `collab:web search`, `collab:patch`, etc.
- `codex_collab_agent_tool_call_event` for cross-agent tool calls

### Cloud Tasks

```
codex_cloud_tasks_apply
codex_cloud_tasks_status
```

- Remote task execution on cloud environments
- Task submission: `Submitting new task`
- Task loading: `Loaded tasks`
- Task cancellation: `Canceled new task`

---

## 11. Telemetry & Analytics

### Metric Events (from string extraction)

```
codex.turn.token_usage        — prompt/completion/reasoning tokens
codex.turn.ttfm.duration_ms   — time to first token
codex.turn.unified_exec.running_processes — active process count
codex.artifact.operation.started         — tool execution start
codex.artifact.operation.expected        — tool execution expected
codex.thread.started                     — thread lifecycle
codex_multi_agent.nickname_pool_reset    — agent pool management
```

### OpenTelemetry Integration

```rust
// From codex-rs/otel
error,opentelemetry_sdk=off,opentelemetry_otlp=off
```

- OTLP export support (disabled by default)
- Custom event mapping via `event_mapping.rs`

---

## 12. Configuration System

### Config Layers (`codex_config`)

```
ConfigLayerStack → ConfigLayerSource → Config
```

Sources (in priority order):
1. CLI arguments
2. Environment variables
3. `.codex/config.toml` (workspace-local)
4. `~/.codex/config.toml` (user-global)
5. Built-in defaults

### Key Config Types

```toml
# .codex/config.toml
wire_api = "responses"          # "chat" deprecated
include_permissions_instructions = true
include_apps_instructions = true
include_collaboration_mode_instructions = true

[shell]
environment_policy = "inherit"

[network]
proxy_url = "..."
socks_url = "..."
enable_socks5 = false
enable_socks5_udp = false
```

---

## 13. Feature Flags (`codex_features`)

### Legacy Features

```
codex_features::legacy
├── message_alias_canonical
├── codex_apps
├── connectors
├── enable_experimental_windows_sandbox
├── experimental_use_unified_exec_tool
├── request_permissions
├── imagegen
├── extcollab
├── memory_tool
├── telepathy
└── codex_hooks
```

---

## 14. Error Handling & Recovery

### Unreachable Code Patterns

From string extraction, Codex has several `unreachable` assertions:
- `internal error: entered unreachable code: expiration wait only resolves while expiration is active`
- `internal error: entered unreachable code: failed to match bind`
- `internal error: entered unreachable code`

These indicate strict invariant enforcement — the Rust equivalent of "this should never happen."

### Retry Mechanisms

```rust
// responses_retry.rs
retries, max_retries, compact_error
// On sampling error: "remote compaction v2 stream failed; retrying request after delay"
```

---

## 15. Lessons for Adventurers Harness

### What Codex Does Better

| Area | Codex Approach | Adventurers Current | Gap |
|------|---------------|---------------------|-----|
| **Exec Policy** | Rule-based with `.rules` files | Binary risk levels | Need rule engine |
| **Approval Flow** | Granular per-tool + per-session | Simple RiskLevel enum | Need escalation tiers |
| **Sandbox** | 3 tiers with Seatbelt SBPL | 3 tiers (matching) | ✅ Parity |
| **Context Compaction** | `compact_remote_v2` with anchors | `TrajectoryCompressor` | Need remote compaction |
| **State Persistence** | Rollout files + SQLite state DB | `EventJournal` JSONL | Need structured persistence |
| **Multi-Agent** | Subagent spawn/resume/close | MetaHarness subprocess | Need actor-based mesh |
| **Plugin System** | Marketplace + git-based sync | None | Need plugin architecture |
| **Network Policy** | Per-protocol rules + proxy | None | Need network gate |
| **Telemetry** | OpenTelemetry + custom events | Sliding window TPS | Need OTLP export |
| **Config Layers** | 5-layer stack with defaults | `HarnessConfig` flat | Need layered config |

### What Adventurers Does Better

| Area | Adventurers Advantage |
|------|----------------------|
| **Swift 6 Concurrency** | Native actors, structured concurrency, Sendable safety |
| **macOS Integration** | SwiftUI native UI, APFS snapshots, Apple Silicon optimization |
| **Deterministic Gates** | 6 explicit gates vs Codex's implicit policy engine |
| **FailChain Escalation** | Progressive feedback for repeated failures |
| **Cost Metering** | Multi-model pricing registry with real-time TPS |
| **In-App Updates** | GitHub Releases auto-updater |

---

## 16. Implementation Priorities

Based on this analysis, the following features should be ported from Codex to Adventurers Harness:

### P0 — Critical for Parity
1. **Rule-based exec policy** — Replace binary RiskLevel with `.adventurers/rules` file
2. **Network gate** — Add network permission checking to gate pipeline
3. **Structured state persistence** — Replace JSONL journal with SQLite-backed state
4. **Tool approval escalation** — Granular per-tool approval with session-level overrides

### P1 — High Value
5. **Context compaction v2** — Remote compaction with anchor preservation
6. **Plugin marketplace** — Git-based plugin distribution and sync
7. **OpenTelemetry export** — OTLP-compatible telemetry pipeline
8. **Layered config system** — 5-layer config stack (CLI → env → workspace → user → defaults)

### P2 — Competitive Advantage
9. **Actor-based multi-agent** — Replace subprocess dispatch with Swift actor mesh
10. **APFS snapshot rollbacks** — Instant workspace snapshots before high-risk operations
11. **SourceKit-LSP integration** — Real-time compilation gates without disk writes
12. **Apple Neural Engine embeddings** — Local codebase search via Accelerate framework
