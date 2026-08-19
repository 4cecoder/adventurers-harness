# Implementation Details — What Real Code Reveals

> Extracted from actual decompiled functions (Muse) and source code (Codex).
> These are the pitfalls, minutia, and nuances that blueprints and strings miss.

---

## 1. Exec Policy Decision Tree (Codex — `exec_policy.rs`)

The policy engine is NOT a simple allow/deny. It's a **multi-layered decision cascade**:

```
Command arrives
  │
  ├─ Check execpolicy rules (loaded from .codex/rules/*.rules files)
  │   ├─ Explicit ALLOW rule → ExecApprovalRequirement::Skip { bypass_sandbox }
  │   ├─ Explicit DENY rule → ExecApprovalRequirement::Forbidden { reason }
  │   └─ PROMPT rule → ExecApprovalRequirement::NeedsApproval
  │
  ├─ No rule matched → fallback to render_decision_for_unmatched_command():
  │   ├─ is_known_safe_command() AND !complex_parsing
  │   │   AND (UnlessTrusted OR WindowsManagedFs)
  │   │   → Allow (sandbox enforces)
  │   │
  │   ├─ dangerous_command_match() OR WindowsManagedFs
  │   │   ├─ AskForApproval::Never → FORBIDDEN (fail-closed)
  │   │   └─ Otherwise → Prompt
  │   │
  │   └─ None of above → match on approval_policy:
  │       ├─ Never → Allow (sandbox enforces)
  │       ├─ UnlessTrusted → Prompt (safelist already failed)
  │       ├─ OnRequest → Allow if Unrestricted/ExternalSandbox
  │       │               Prompt if Restricted + sandbox_override
  │       └─ Granular → Same as OnRequest
  │
  └─ Final check: prompt_is_rejected_by_policy()
      └─ If rejected → ExecApprovalRequirement::Forbidden
```

### Critical Nuance: `bypass_sandbox: all_segments_explicitly_allowed`

When a command is ALLOWED by an explicit rule, the sandbox bypass is **not automatic**. It only happens if **every segment** of the command was explicitly allowed. This prevents:
- `git status` (safe) from bypassing sandbox when `git push --force` is in the same pipeline
- Shell wrappers from inheriting sandbox bypass from safe arguments

### Critical Nuance: `BANNED_PREFIX_SUGGESTIONS`

46 shell prefixes are **never auto-suggested** as reusable approval amendments:
```rust
["bash", "-c"], ["bash", "-lc"],
["zsh", "-c"], ["zsh", "-lc"],
["sh", "-c"], ["sh", "-lc"],
["node", "-e"], ["npm", "run"],
["python", "-c"], ["Rscript"],
["osascript"], ["deno", "eval"],
// ... 46 total
```

This prevents users from accidentally approving `bash -c 'rm -rf /'` as a reusable prefix.

### Critical Nuance: Policy Amendment Atomicity

```rust
// append_amendment_and_update uses Semaphore(1) for update_lock
// This prevents:
//   1. Two concurrent amendments from racing
//   2. Amendment being read mid-write by policy evaluation
//   3. Disk write being interrupted by another amendment
```

---

## 2. Guardian Review Circuit Breaker (Codex — `guardian/mod.rs`)

The guardian has **two independent circuit breakers**:

```rust
// Cyber models (more aggressive): 
MAX_CONSECUTIVE_CYBER_GUARDIAN_DENIALS_PER_TURN = 1
MAX_RECENT_CYBER_AUTO_REVIEW_DENIALS_PER_TURN = 1

// Standard models:
MAX_CONSECUTIVE_GUARDIAN_DENIALS_PER_TURN = 3
MAX_RECENT_AUTO_REVIEW_DENIALS_PER_TURN = 10

// Shared window:
AUTO_REVIEW_DENIAL_WINDOW_SIZE = 50  // recent_denials deque
```

### How It Works:

```
For each tool call:
  1. Run guardian review (up to 3 retry attempts on transient errors)
  2. If DENIED:
     - consecutive_denials += 1
     - Push to recent_denials deque (max 50 entries)
     - Check: consecutive >= max_consecutive OR recent >= max_recent
     - If exceeded → InterruptTurn (stops the entire turn)
  3. If APPROVED:
     - consecutive_denials = 0
     - (recent_denials NOT cleared — history matters)
```

### Critical Nuance: Transient Error Retry

```rust
// ONLY retry on these errors:
- ServerOverloaded
- HttpConnectionFailed
- ResponseStreamConnectionFailed
- InternalServerError
- ResponseStreamDisconnected
- Parse (malformed JSON from model)

// DO NOT retry on:
- Authorization errors
- Rate limiting
- Invalid requests
```

### Critical Nuance: Fail-Closed on Guardian Error

```rust
// If guardian review fails with Session/Parse/PromptBuild error:
//   → RiskLevel::High, Outcome::Deny
// The guardian NEVER fails open. Errors are treated as "deny".
```

---

## 3. Context Compaction v2 (Codex — `compact_remote_v2.rs`)

### Token Budget Hard Limits:

```rust
RETAINED_MESSAGE_TOKEN_BUDGET = 64_000      // Total budget for retained messages
MAX_RETAINED_AGENT_MESSAGE_TOKENS = 10_000  // Max tokens per retained agent message
MAX_REMOTE_COMPACTION_V2_STREAM_RETRIES = 2  // Retries before fallback model
```

### What Gets Retained vs Dropped:

```rust
fn is_retained_for_remote_compaction_v2(item) -> bool {
    match item {
        AgentMessage => !is_final_answer && token_count <= 10_000,
        Message => role == "user" || role == "developer" || role == "system",
        _ => false,  // Everything else is DROPPED
    }
}
```

### Truncation Algorithm (newest→oldest):

```
1. Start with newest messages, fill budget (64K tokens)
2. Client-authored developer messages: charge FULL item tokens
3. Regular messages: charge only TEXT tokens (not metadata)
4. Images: count toward budget but DON'T truncate
5. When budget exhausted: truncate text to fit remaining budget
6. Initial context inserted BEFORE last user message
```

### Critical Nuance: Compaction Output Placement

```rust
// The compaction summary is NOT appended to the end.
// It's inserted BEFORE the last user message:
//   [retained messages] → [compaction summary] → [last user message]
// This preserves the "user's latest request is always visible" invariant.
```

---

## 4. Guardian Prompt Budget (Codex — `guardian/prompt.rs`)

The guardian has **hard token limits** for transcript rendering:

```rust
GUARDIAN_MAX_MESSAGE_TRANSCRIPT_TOKENS = 10_000  // Total for messages
GUARDIAN_MAX_TOOL_TRANSCRIPT_TOKENS = 10_000     // Total for tool outputs
GUARDIAN_MAX_MESSAGE_ENTRY_TOKENS = 2_000        // Per-message limit
GUARDIAN_MAX_TOOL_ENTRY_TOKENS = 1_000           // Per-tool-output limit
GUARDIAN_MAX_NODE_REPL_TOOL_RESULT_TOKENS = 6_000 // Node REPL special limit
GUARDIAN_MAX_ACTION_STRING_TOKENS = 16_000       // Action description limit
GUARDIAN_RECENT_ENTRY_LIMIT = 40                 // Max entries in transcript
GUARDIAN_MAX_APPROVAL_REASON_TOKENS = 512        // Approval reason limit
```

### Selection Algorithm:

```
1. ALWAYS include first and last user turns as anchors
2. Fill remaining message budget with user turns (newest→oldest)
3. Fill remaining budget with non-user entries (newest→oldest), up to 40 entries
4. Tool entries share tool budget; message entries share message budget
5. Per-entry truncation: messages 2000 tokens, tools 1000 tokens
```

### Critical Nuance: Developer Message Filtering

```rust
// Developer messages are ONLY kept if they start with:
AUTO_REVIEW_DENIED_ACTION_APPROVAL_DEVELOPER_PREFIX
// This means most developer messages are DROPPED from guardian transcript.
// Only auto-review markers are retained.
```

---

## 5. Network Policy Decision (Codex — `network_policy_decision.rs`)

### Decision Mapping:

```rust
fn denied_network_policy_message(reason) -> String {
    match reason {
        "denied" => "domain is explicitly denied...",
        "not_allowed" => "domain is not on the allowlist...",
        "not_allowed_local" => "local/private network addresses are blocked...",
        "method_not_allowed" => "request method is blocked...",
        "proxy_disabled" => "network proxy is disabled",
    }
}
```

### Protocol Mapping:

```rust
fn execpolicy_network_rule_amendment(protocol) -> NetworkRuleProtocol {
    match protocol {
        Http => Http,
        Https => Https,
        Socks5Tcp => Socks5Tcp,
        Socks5Udp => Socks5Udp,
    }
}
```

### Critical Nuance: `is_ask_from_decider`

```rust
// network_approval_context is ONLY created if:
//   is_ask_from_decider AND host.is_empty() == false
// This prevents empty hosts from generating approval requests
```

---

## 6. Muse Sandbox Implementation (Decompiled)

### Runtime Bootstrap (`spawn_with_config_and_reviewer` at `0x1011e7894`):

```rust
// 1. Copy 0x2D60-byte config struct (NOT pointer — full copy)
// 2. Create Tokio current-thread runtime with 393KB stack
// 3. Wire approval reviewer as sub-task
// 4. Enter runtime block_on
```

### Sandbox Manager (`SandboxManager::prepare_process` at `0x105156eb8`):

```rust
// Platform dispatch:
match platform {
    macOS = 2 => macos::wrap_command(),
    Linux = 3 => linux::wrap_command(),
}

// macOS seatbelt construction:
fn macos::wrap_command(command, permissions) {
    // Explicit allow rules:
    - process-exec
    - process-fork
    - sysctl-read
    - file-read* (all paths)
    - system-socket (AF_UNIX)
    - network-bind (local unix-socket)
    - network-outbound (remote unix-socket)
    
    // Deny everything else (deny default)
    // Read-only paths: explicit subpath rules
}
```

### Critical Nuance: YOLO Mode

```rust
// YOLO mode disables BOTH approval AND sandbox:
// --yolo flag
// This means:
//   - No approval prompts
//   - No seatbelt sandbox
//   - No network restrictions
//   - Tool execution is UNRESTRICTED
// The safety message explicitly warns: "YOLO mode is already on"
```

---

## 7. Muse Approval System (Decompiled)

### Approval Assessment Structure:

```rust
struct ApprovalAssessment {
    risk_level: RiskLevel,        // low, medium, high, critical
    user_authorization: AuthLevel, // unknown, low, medium, high
    outcome: Outcome,             // approve, escalate, deny
    rationale: String,            // explanation
}
```

### Terminal States (6 total):

```
1. approved       - User approved the action
2. denied         - User denied the action
3. timed_out      - Approval window expired
4. aborted        - Session was cancelled
5. escalated      - Forwarded to higher authority
6. auto_approved  - Approved by automated policy
```

### Critical Nuance: Policy Amendment Persistence

```rust
// Approval decisions can be persisted as PolicyAmendment:
//   - "Always allow this command prefix"
//   - "Always deny this network host"
//   - Stored in .muse/config.toml
//   - Applied to future requests automatically
```

---

## 8. Muse Workflow Recovery (Decompiled)

### Recovery Failure Modes (22+):

```
workflow recovery owner registration failed for run
workflow recovery source projection preflight failed
workflow live startup requires a durable session log
workflow recovery apply failed for run
workflow live recovery current-source composition failed
workflow-live-recovery: generated prompt workflow exceeded total agent-call cap
workflow recovery could not bind tools to retained worktree
workflow recovery could not rehydrate retained worktree source proof
workflow recovery retained worktree cwd is invalid
workflow recovery retained worktree is missing
workflow resume index run listing failed
workflow resume index run read failed
workflow recovery failed for run
workflow recovery failed: system clock is before UNIX epoch
workflow recovery failed: retained session stream
```

### Critical Nuance: Worktree Lease System

```rust
// Subagents use LEASE-BASED ownership:
//   - Worktree is "leased" to a subagent
//   - Lease has an owner session ID
//   - Other subagents CANNOT use a leased worktree
//   - Lease expires on session end
//   - "quarantined subagent worktree lease: owner session" on conflict
```

### Critical Nuance: Source Proof Validation

```rust
// On recovery, the system validates:
//   1. Retained worktree still exists
//   2. Source root matches recorded root
//   3. Source identity (git hash) matches recorded proof
//   4. If ANY check fails → recovery ABORTS
// This prevents recovering into a modified workspace
```

---

## 9. What Blueprints Miss — The Minutia

### 1. Token Counting Is Approximate
```rust
// Codex uses: content.count() / 4 as token estimate
// This is ~25% off for code (code has more tokens per char)
// But it's FAST — no model call needed
```

### 2. Truncation Is Recursive
```rust
// JSON values are truncated recursively:
//   Strings → guardian_truncate_text()
//   Arrays → truncate each element
//   Objects → sort by key, truncate each value
// Returns (value, was_truncated) tuple
```

### 3. Concurrency Guards Are Everywhere
```rust
// Semaphore(1) for policy amendments
// NSLock for process registry
// Actor isolation for state engines
// Every mutable shared state has a guard
```

### 4. Error Messages Are Structured
```rust
// Every error includes:
//   - Module path (e.g., "core/src/exec_policy.rs:684")
//   - Error kind (e.g., "codex_core::exec_policy")
//   - Human-readable message
// This enables automated error classification
```

### 5. Telemetry Is Baked In
```rust
// Every decision emits events:
//   codex.turn.token_usage
//   codex.turn.ttfm.duration_ms
//   codex.artifact.operation.started
//   codex.thread.started
// Even errors emit events for tracking
```

### 6. Retry Logic Is Specific
```rust
// Retries ONLY on transient errors:
//   ServerOverloaded, HttpConnectionFailed, etc.
// NEVER on: Authorization, RateLimit, InvalidRequest
// Max retries: 2 (with fallback model)
```

### 7. Safety Is Fail-Closed
```rust
// Guardian error → Deny (not Allow)
// Unknown command → Prompt (not Allow)
// Policy parse error → Forbidden
// The system NEVER fails open
```

---

## 10. Implementation Priorities for Adventurers Harness

Based on real code analysis, these are the **exact implementations** needed:

| Priority | Feature | Codex Pattern | Muse Pattern | Our Gap |
|----------|---------|---------------|--------------|---------|
| P0 | Exec policy rules | `.rules` files with multi-layer cascade | `PolicyAmendment` persistence | Need rule engine |
| P0 | Guardian circuit breaker | Dual thresholds (consecutive + window) | 6 terminal states | Need circuit breaker |
| P0 | Fail-closed safety | Errors → Deny, never Allow | YOLO mode warning | Need fail-closed default |
| P1 | Context compaction v2 | 64K budget, 10K per-message, anchor preservation | 26-field checkpoint | Need budget limits |
| P1 | Token budget enforcement | Hard limits per entry, recursive truncation | Soft/hard thresholds | Need per-entry limits |
| P1 | Network policy | Protocol-level allow/deny with proxy | Network sandbox modes | Need protocol filtering |
| P2 | Worktree lease system | N/A | Lease-based ownership | Need workspace isolation |
| P2 | Source proof validation | N/A | Git hash validation on recovery | Need integrity checks |
| P2 | Policy amendment atomicity | Semaphore(1) for updates | PolicyAmendment storage | Need atomic updates |
