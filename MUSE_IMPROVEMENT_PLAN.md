# Adventurers Harness — Muse-Inspired Improvement Plan

> **Goal**: Borrow proven architecture patterns from Meta's Muse Code to make Adventurers Harness more robust, session-aware, and production-ready.

---

## Executive Summary

After reverse-engineering Muse Binary (0.2.1-R1215.1), we identified **12 high-value architectural patterns** that Adventurers Harness can adopt. These improvements focus on session durability, workflow recovery, and production-grade reliability — areas where Muse excels and Adventurers currently has gaps.

---

## Key Differences: Adventurers vs Muse

| Feature | Adventurers | Muse | Gap |
|---------|-------------|------|-----|
| Language | Swift 6 (macOS) | Rust (cross-platform) | — |
| Session persistence | In-memory only | JSONL logs + checkpoints | **Critical** |
| Workflow recovery | None | Live recovery from retained logs | **Critical** |
| Subagent system | Basic process dispatch | Native worktree-isolated children | High |
| Approval system | Gate-based (static) | Dynamic approval with judges | Medium |
| Context management | Manual | Auto-compaction + pruning | High |
| Tool sandboxing | Darwin Seatbelt | Seatbelt + network policy | Low |
| Model catalog | Static config | Dynamic fetch + caching | Medium |
| Goal tracking | Task contracts | GoalService with progress nudges | Medium |
| Error recovery | Crash → restart | Checkpoint → resume | **Critical** |

---

## Improvement Plan: 12 Features to Adopt

### 1. Durable Session Logs (JSONL) — CRITICAL

**Muse Pattern:** Every session writes to a JSONL log file. Sessions can be resumed, replayed, or recovered from crashes.

**Current Adventurers:** Sessions are in-memory only. App crash = lost work.

**Implementation:**
```swift
// New file: Sources/AdventurersCore/SessionLog.swift
struct SessionLog {
    let sessionId: UUID
    let logFile: URL  // ~/.adventurers/sessions/{id}.jsonl
    
    func append(event: SessionEvent) throws
    func replay(from sequence: SequenceNumber) throws -> [SessionEvent]
    func checkpoint() throws -> Checkpoint
}
```

**Files to create:**
- `Sources/AdventurersCore/SessionLog.swift`
- `Sources/AdventurersCore/SessionEvent.swift`
- `Sources/AdventurersCore/SessionStorage.swift`

**Priority:** P0 — Do this first. Everything else depends on durable sessions.

---

### 2. Checkpoint & Resume System — CRITICAL

**Muse Pattern:** Sessions create checkpoints at key moments. On crash, resume from last checkpoint instead of restarting.

**Current Adventurers:** No resume capability. User must manually redo work.

**Implementation:**
```swift
struct Checkpoint {
    let sequenceNumber: SequenceNumber
    let timestamp: Date
    let contextSnapshot: ContextState
    let pendingToolCalls: [ToolCall]
    let modelMessages: [ModelMessage]
}

func resume(from checkpoint: Checkpoint) async throws {
    // Restore context state
    // Re-queue pending tool calls
    // Continue model conversation
}
```

**Files to create:**
- `Sources/AdventurersCore/Checkpoint.swift`
- `Sources/AdventurersCore/CheckpointManager.swift`

**Priority:** P0 — Build on top of session logs.

---

### 3. Workflow Recovery Engine — HIGH

**Muse Pattern:** Interrupted workflows can be recovered by replaying retained session logs and rehydrating state.

**Current Adventurers:** No workflow recovery. Long-running tasks must restart from scratch.

**Implementation:**
```swift
struct WorkflowRecovery {
    func detectInterruptedWorkflows() -> [RetainedWorkflow]
    func rehydrate(workflow: RetainedWorkflow) async throws -> ResumedWorkflow
    func validateRecoveryIntegrity(_ workflow: ResumedWorkflow) throws
}
```

**Key concepts to adopt:**
- `workflow-live-recovery:` — Live recovery protocol
- `retained session stream` — Persisted event stream
- `source projection` — Reconstruct state from logs
- `worktree retention` — Preserve isolated workspaces

**Files to create:**
- `Sources/AdventurersCore/WorkflowRecovery.swift`
- `Sources/AdventurersCore/RetainedWorkflow.swift`

**Priority:** P1 — Requires session logs first.

---

### 4. Native Subagent System — HIGH

**Muse Pattern:** Subagents run in isolated worktrees with lease-based access control. Parent-child relationships are tracked via goal bindings.

**Current Adventurers:** Basic `MetaHarness` subprocess dispatch with process isolation only.

**Improvements to adopt:**

| Feature | Current | Muse-Inspired |
|---------|---------|---------------|
| Isolation | Process only | Worktree + process |
| Lifecycle | Fire-and-forget | Managed queue with retries |
| Result delivery | stdout capture | Structured result objects |
| Error handling | Crash detection | Attempt selection + recovery |
| Lease system | None | Worktree lease prevents conflicts |

**Implementation sketch:**
```swift
class NativeSubagentManager {
    func spawn(
        task: SubagentTask,
        worktree: WorktreeLease,
        tools: [ToolDefinition]
    ) async throws -> SubagentHandle
    
    func drainQueue() async throws
    func settleChildren() async throws
}
```

**Files to create:**
- `Sources/AdventurersCore/NativeSubagentManager.swift`
- `Sources/AdventurersCore/WorktreeLease.swift`
- `Sources/AdventurersCore/SubagentHandle.swift`

**Priority:** P1 — Critical for multi-agent workflows.

---

### 5. Dynamic Model Catalog — MEDIUM

**Muse Pattern:** Model list is fetched from API at runtime, cached locally, refreshed periodically. Supports model switching mid-session.

**Current Adventurers:** Static model config in `opencode.json`.

**Improvements:**
```swift
class ModelCatalog {
    func fetchFromProvider() async throws -> ModelList
    func cache(_ catalog: ModelList) throws
    func refreshIfNeeded() async throws
    func selectModel(id: String) throws -> Model
    func supportsFeature(_ feature: ModelFeature) -> Bool
}
```

**Benefits:**
- Auto-discover new models
- Dynamic context limits per model
- Model switching without restart
- Provider-specific optimizations

**Files to create:**
- `Sources/AdventurersCore/ModelCatalog.swift`
- `Sources/AdventurersCore/ModelList.swift`

**Priority:** P2 — Nice to have, not blocking.

---

### 6. Goal & Task Tracking System — MEDIUM

**Muse Pattern:** `GoalService` tracks long-running objectives with progress nudges, usage attribution, and descendant tracking.

**Current Adventurers:** `TaskContractProgressCard` exists but is static.

**Improvements to adopt:**
- **Goal hierarchy:** Parent goals with child sub-goals
- **Progress nudges:** Periodic reminders to check progress
- **Usage attribution:** Track token/cost per goal
- **Goal binding:** Link tool calls to specific goals
- **Goal completion:** Verify against concrete requirements

**Implementation sketch:**
```swift
struct Goal {
    let id: GoalId
    let parentId: GoalId?
    let objective: String
    var status: GoalStatus
    var children: [Goal]
    var usage: GoalUsage
}

class GoalService {
    func onMainLLMCall() async
    func trackProgress(goalId: GoalId) async
    func attributeUsage(goalId: GoalId, usage: TokenUsage)
}
```

**Files to create:**
- `Sources/AdventurersCore/GoalService.swift`
- `Sources/AdventurersCore/Goal.swift`
- `Sources/AdventurersCore/GoalUsage.swift`

**Priority:** P2 — Improves long-horizon task management.

---

### 7. Context Compaction & Pruning — MEDIUM

**Muse Pattern:** Auto-compaction reduces context size by summarizing older messages. Preserved segments keep critical context.

**Current Adventurers:** Manual context management. Long conversations hit limits.

**Implementation:**
```swift
class ContextCompactor {
    func compact(messages: [Message], budget: TokenBudget) -> CompactedContext {
        // 1. Identify summary candidates
        // 2. Generate summary for old messages
        // 3. Preserve critical segments (tool results, errors)
        // 4. Rebuild context within budget
    }
}

struct PreservedSegment {
    let start: SequenceNumber
    let end: SequenceNumber
    let reason: PreservationReason
}
```

**Benefits:**
- Stay within context limits
- Preserve important context
- Reduce costs
- Enable longer sessions

**Files to create:**
- `Sources/AdventurersCore/ContextCompactor.swift`
- `Sources/AdventurersCore/PreservedSegment.swift`

**Priority:** P2 — Enables longer-running sessions.

---

### 8. Approval Judge System — MEDIUM

**Muse Pattern:** Automated approval judges review tool calls. Supports `allow_all`, `deny_unmatched`, `on_request`, `prompt_unmatched` modes.

**Current Adventurers:** Static gate-based approval only.

**Improvements:**
- **Automated judges:** LLM-based approval for complex decisions
- **Approval modes:** Granular control per tool type
- **Policy persistence:** Save approval decisions for reuse
- **Network approval:** Remote approval requests
- **Approval audit trail:** Track all approval decisions

**Implementation sketch:**
```swift
enum ApprovalMode {
    case allowAll
    case denyUnmatched
    case onRequest
    case promptUnmatched
    case granular(GranularPolicy)
}

class ApprovalJudge {
    func review(toolCall: ToolCall, context: ApprovalContext) async -> ApprovalDecision
    func persistDecision(_ decision: ApprovalDecision) throws
    func loadPolicy() -> ApprovalPolicy
}
```

**Files to create:**
- `Sources/AdventurersCore/ApprovalJudge.swift`
- `Sources/AdventurersCore/ApprovalPolicy.swift`
- `Sources/AdventurersCore/ApprovalMode.swift`

**Priority:** P2 — Improves security and flexibility.

---

### 9. Network Sandbox Policy — LOW

**Muse Pattern:** Fine-grained network control: `allow_all`, `deny_all`, `allow_list`, `deny_list`.

**Current Adventurers:** Darwin Seatbelt handles filesystem, but no network policy.

**Implementation:**
```swift
enum NetworkSandboxPolicy {
    case allowAll
    case denyAll
    case allowList([String])  // hostnames
    case denyList([String])
}

func applyNetworkPolicy(_ policy: NetworkSandboxPolicy) throws
```

**Files to create:**
- `Sources/AdventurersCore/NetworkSandbox.swift`

**Priority:** P3 — Security hardening.

---

### 10. Session Worktree Isolation — LOW

**Muse Pattern:** Each session gets its own worktree. Worktrees have lease-based access control. Cleanup on session end.

**Current Adventurers:** All sessions share the same workspace.

**Implementation:**
```swift
class WorktreeManager {
    func createWorktree(for session: Session) throws -> Worktree
    func acquireLease(_ worktree: Worktree) throws -> WorktreeLease
    func releaseLease(_ lease: WorktreeLease) throws
    func cleanup(_ worktree: Worktree) throws
}
```

**Files to create:**
- `Sources/AdventurersCore/WorktreeManager.swift`
- `Sources/AdventurersCore/Worktree.swift`

**Priority:** P3 — Enables concurrent safe sessions.

---

### 11. Tool Hook System — LOW

**Muse Pattern:** Hooks can intercept, modify, or block tool calls. Used for security policy enforcement.

**Current Adventurers:** No hook system. Gates are applied post-hoc.

**Implementation:**
```swift
protocol ToolHook {
    func beforeToolCall(_ call: ToolCall) async throws -> ToolCall
    func afterToolCall(_ call: ToolCall, result: ToolResult) async throws -> ToolResult
    func shouldBlock(_ call: ToolCall) -> Bool
}

class HookManager {
    func register(_ hook: ToolHook)
    func executeHooks(for call: ToolCall) async throws -> HookResult
}
```

**Files to create:**
- `Sources/AdventurersCore/ToolHook.swift`
- `Sources/AdventurersCore/HookManager.swift`

**Priority:** P3 — Extensibility feature.

---

### 12. Voice Input Support — LOW

**Muse Pattern:** Audio input via AudioUnit framework. Voice commands for hands-free operation.

**Current Adventurers:** Text-only input.

**Implementation:** Use existing AudioUnit imports to add:
- Voice command recognition
- Audio transcription
- Hands-free mode

**Files to create:**
- `Sources/AdventurersCore/VoiceInput.swift`

**Priority:** P4 — Accessibility feature.

---

## Implementation Roadmap

### Phase 1: Session Durability (Weeks 1-2)
- [ ] Implement JSONL session logging
- [ ] Add checkpoint creation at key moments
- [ ] Build checkpoint resume capability
- [ ] Test crash recovery

### Phase 2: Workflow Recovery (Weeks 3-4)
- [ ] Build workflow detection for interrupted tasks
- [ ] Implement state rehydration from logs
- [ ] Add worktree retention and cleanup
- [ ] Test recovery scenarios

### Phase 3: Subagent System (Weeks 5-6)
- [ ] Extend MetaHarness with worktree isolation
- [ ] Add lease-based access control
- [ ] Implement result delivery and attempt selection
- [ ] Test concurrent subagent execution

### Phase 4: Intelligence Features (Weeks 7-8)
- [ ] Dynamic model catalog
- [ ] Goal tracking with progress nudges
- [ ] Context compaction
- [ ] Approval judge system

### Phase 5: Security & Polish (Weeks 9-10)
- [ ] Network sandbox policy
- [ ] Tool hook system
- [ ] Session worktree isolation
- [ ] Voice input (optional)

---

## Quick Wins (Can implement immediately)

1. **Session log append** — Write events to JSONL file
2. **Checkpoint on tool completion** — Save state after each tool call
3. **Resume from last checkpoint** — On app restart, offer to resume
4. **Goal progress display** — Show progress in UI
5. **Model catalog cache** — Fetch and cache model list

---

## Testing Strategy

### Crash Recovery Tests
```swift
func testCrashRecovery() throws {
    let session = Session.log
    session.append(.userMessage("Fix the bug"))
    session.append(.toolCall(.init(name: "bash", args: ["make test"])))
    session.checkpoint()
    
    // Simulate crash
    let newSession = Session.resume(from: session.lastCheckpoint)
    XCTAssertEqual(newSession.pendingToolCalls.count, 1)
}
```

### Workflow Recovery Tests
```swift
func testWorkflowRecovery() throws {
    let workflow = try createTestWorkflow()
    let checkpoint = try workflow.checkpoint()
    
    // Simulate interruption
    let recovered = try WorkflowRecovery.rehydrate(checkpoint)
    XCTAssertEqual(recovered.status, .resumed)
}
```

---

## Metrics to Track

| Metric | Current | Target |
|--------|---------|--------|
| Crash recovery rate | 0% | 95% |
| Session resume time | N/A | < 2s |
| Workflow recovery success | N/A | 85% |
| Context compaction ratio | N/A | 3:1 |
| Subagent spawn latency | ~500ms | < 200ms |

---

## References

- Muse Binary: `ida-workspace/muse-binary`
- Full Analysis: `ida-workspace/MUSE_BINARY_ANALYSIS.md`
- Radare2 Report: `ida-workspace/r2_muse_analysis/comprehensive_report.txt`
- IDA Script: `ida-workspace/scripts/analyze_muse_full.py`

---

*Created: 2026-08-19*
*Based on: Muse Binary 0.2.1-R1215.1 reverse engineering*
