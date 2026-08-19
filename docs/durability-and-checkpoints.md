# Session Durability, JSONL Streaming & Checkpoint Rollbacks

> **Design Principle**: *Zero data loss across unexpected reboots, crashes, or interrupted tool calls.*

---

## 1. Append-Only JSONL Event Streaming (`SessionLog.swift`)

Every turn in Adventurers Harness is written to an append-only JSONL log at `~/.adventurers/sessions/{threadID}.jsonl`.

### Event Schema

```json
{"id":"evt_01","timestamp":"2026-08-19T12:00:00Z","threadID":"40391518-...","type":"user_prompt","turnIndex":0,"payload":{"text":"Refactor auth"},"tokenCount":14}
{"id":"evt_02","timestamp":"2026-08-19T12:00:02Z","threadID":"40391518-...","type":"thought","turnIndex":1,"payload":{"thought":"Inspecting file layout"},"tokenCount":30}
{"id":"evt_03","timestamp":"2026-08-19T12:00:03Z","threadID":"40391518-...","type":"tool_call","turnIndex":1,"payload":{"tool":"bash","command":"swift test"},"tokenCount":20}
{"id":"evt_04","timestamp":"2026-08-19T12:00:06Z","threadID":"40391518-...","type":"tool_result","turnIndex":1,"payload":{"tool":"bash","output":"All 43 tests passed"},"tokenCount":15}
```

### Supported Event Types

| Event Type | Trigger | Disk Payload |
|---|---|---|
| `session_started` | Thread creation | Model name, working directory |
| `user_prompt` | User submits prompt | Raw prompt text |
| `thought` | Agent internal reasoning | CoT / reasoning buffer |
| `assistant_text` | Agent conversational text | Markdown message body |
| `tool_call` | Agent proposes tool execution | Tool name, arguments/command |
| `tool_result` | Tool completes execution | Exit code, stdout/stderr |
| `gate_certification` | Programmatic gate runs | Gate name, pass/fail status |
| `checkpoint_created` | Pre-mutation file snapshot | Checkpoint ID, affected files |
| `checkpoint_restored` | User triggers rollback | Restored file count |
| `error` | System or provider error | Error domain, error code, message |

---

## 2. Checkpoint Persistence & 1-Click Rollback (`CheckpointPersistence.swift`)

Prior to any destructive file mutation or patch application, `SessionCheckpointEngine` creates an atomic disk checkpoint stored in `~/.adventurers/checkpoints/{sessionID}/{checkpointID}.json`.

```swift
public struct SessionCheckpoint: Sendable, Codable, Identifiable {
    public let id: UUID
    public let turnNumber: Int
    public let timestamp: Date
    public let summary: String
    public let snapshots: [FileSnapshot]
    public let affectedFiles: [String]
}
```

### Rollback Process

1. User clicks **"Rollback to Turn #N"** or harness detects repeated failure loops.
2. `CheckpointPersistence.rollbackToDiskCheckpoint()` reads original file contents from the JSON snapshot.
3. Target workspace files are overwritten atomically with verification.
4. UI and FSM state revert to the selected checkpoint turn.

---

## 3. Workflow Recovery & Crash Rehydration (`WorkflowRecovery.swift`)

When Adventurers Harness starts up:
1. `WorkflowRecoveryEngine.scanForRecoverableSessions()` scans `~/.adventurers/sessions/`.
2. Inspects the last event in each session's log:
   - If ending in `tool_call`, `thought`, or `error`, marks session as **Interrupted**.
   - Generates contextual recovery recommendations.
3. `rehydrateMessages()` reconstructs the complete `ThreadMessage` conversation tree directly from the JSONL log without relying on memory or cached AppKit state.
