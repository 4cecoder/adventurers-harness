# Meta-Harness Multi-Agent Dispatch

> Architecture, CLI integration, and credential isolation for delegating coding workflows to external agent harnesses.

---

## Overview

Adventurers Harness is designed not only as a standalone coding agent, but as a **Meta-Harness Orchestrator**. When complex tasks require specialized capabilities, the harness can delegate tasks to external sub-agent CLI binaries while supervising their execution, capturing streaming telemetry, and certifying the final code output.

---

## Supported Meta-Harness Targets

| Target Harness | Primary Strength | Default Binary | Injected Env Var |
|----------------|------------------|----------------|-------------------|
| **OpenAI Codex CLI** | Rust-based gate-certified execution with deterministic contracts | `codex` | `CODEX_API_KEY` |
| **Nous Hermes Agent** | Staged reflection with persistent episodic memory & learning loop | `hermes` | `HERMES_API_KEY` |
| **OpenCode CLI** | Go-based multi-provider coding agent with LSP and SQLite sessions | `opencode` | `OPENCODE_API_KEY` |
| **DeepSeek Harness** | Plugin-everything modular architecture for frontier reasoning models | `dsh` | `DEEPSEEK_API_KEY` |
| **Pi Agent Harness** | TypeScript multi-provider autonomous coding and exploration engine | `pi` | `PI_API_KEY` |
| **SmallCTL (FAMA)** | Failure Mitigation Agent optimized for small/medium coding models | `smallctl` | `OPENAI_API_KEY` |
| **Custom Harness** | User-configured external CLI agent or executable runner | `agent-harness` | `AGENT_API_KEY` |

---

## CLI Discovery Pipeline

The `MetaHarnessRegistry` automatically scans the host environment on launch:

1. System `$PATH` directories (`/usr/local/bin`, `/opt/homebrew/bin`, `/usr/bin`)
2. User package managers (`~/.local/bin`, `~/.cargo/bin`, `~/.npm-global/bin`)
3. Workspace research folders (`./research/`)

Found binaries are marked with an `● Auto-Detected` badge in Settings.

---

## Credential Isolation Architecture

To prevent accidental key sharing or unexpected rate limit collisions between interactive coding plans and background meta-harnesses, Adventurers implements **isolated credential scoping**:

1. **Coding Plan Keyring**:
   - Stored in `SettingsModel.providerKeys`.
   - Used exclusively for direct HTTP/SSE cloud streaming.
2. **Meta-Harness Profile Keyring**:
   - Stored in `MetaHarnessProfile.apiKey`.
   - Injected strictly into the subprocess environment table during CLI execution.
3. **One-Click Key Sync**:
   - A dedicated *"Sync All Keys"* action allows instant copying of credentials from Coding Plan keys into corresponding Meta-Harness profiles.

---

## Process Supervision & Lifecycle

When a task is dispatched in Meta-Harness mode:

```
User Prompt
    │
    ▼
ThreadViewModel.sendMessage()
    │
    ▼
MetaHarnessRunner.executeHarness(profile, prompt, workspace)
    │
    ├── Injects Isolated Environment ($CODEX_API_KEY, $PATH, $TERM)
    ├── Spawns zsh child process in workspace directory
    ├── Captures stdout/stderr via non-blocking Async FileHandle readabilityHandlers
    ├── Streams deltas in real-time into ThreadMessage bubble
    ├── Computes live rolling token TPS
    │
    ▼
Process Exits (Status Code)
    │
    ▼
Harness Certification Gates Evaluate Workspace Diffs
    │
    ├── SyntaxGate (Balanced code syntax)
    ├── DiffGate (No destructive commands or sensitive path leaks)
    └── RepeatGate (No duplicate loops)
    │
    ▼
Task Certified & Appended to Event Journal
```
