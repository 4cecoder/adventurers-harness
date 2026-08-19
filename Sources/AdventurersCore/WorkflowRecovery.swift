// AdventurersCore - Pure Swift Workflow Recovery & Rehydration Engine
// Inspired by Muse's tbh_tui::startup::session_log_replay
// Scans persistent JSONL logs and checkpoints on startup to detect interrupted sessions and restore state.

import Foundation

public struct RecoveryCandidate: Sendable, Identifiable {
    public var id: UUID { threadID }
    public let threadID: UUID
    public let sessionName: String
    public let lastEventTimestamp: Date
    public let eventCount: Int
    public let lastEventType: SessionEventType
    public let hasAvailableCheckpoints: Bool
    public let isInterrupted: Bool
    public let recoverySuggestion: String

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: lastEventTimestamp)
    }
}

public actor WorkflowRecoveryEngine {
    public static let shared = WorkflowRecoveryEngine()

    public init() {}

    /// Scans ~/.adventurers/sessions/ to discover all sessions and detect any interrupted ones.
    public func scanForRecoverableSessions() async -> [RecoveryCandidate] {
        let sessionIDs = await SessionLogManager.shared.listSavedSessionIDs()
        var candidates: [RecoveryCandidate] = []

        for id in sessionIDs {
            let events = await SessionLogManager.shared.replayEvents(for: id)
            guard let lastEvent = events.last else { continue }

            let checkpoints = await CheckpointPersistence.shared.loadCheckpoints(for: id)
            let hasCheckpoints = !checkpoints.isEmpty

            // An interrupted session ends on a tool call, prompt, or thought without a sessionTerminated or assistant completion
            let isInterrupted: Bool
            let suggestion: String

            switch lastEvent.type {
            case .sessionTerminated:
                isInterrupted = false
                suggestion = "Session completed normally."
            case .toolCall:
                isInterrupted = true
                suggestion = "Interrupted during tool execution: `\(lastEvent.payload["tool"] ?? "unknown")`. Checkpoints available to rollback or resume."
            case .thought:
                isInterrupted = true
                suggestion = "Interrupted during reasoning. Safe to resume from prompt."
            case .error:
                isInterrupted = true
                suggestion = "Session halted on error: \(lastEvent.payload["message"] ?? ""). Rollback available."
            case .userPrompt:
                isInterrupted = true
                suggestion = "Interrupted waiting for agent response."
            default:
                isInterrupted = false
                suggestion = "Session retained with \(events.count) events."
            }

            let sessionName = events.first(where: { $0.type == .userPrompt })?.payload["text"]
                ?? "Session #\(id.uuidString.prefix(6))"

            let candidate = RecoveryCandidate(
                threadID: id,
                sessionName: String(sessionName.prefix(60)),
                lastEventTimestamp: lastEvent.timestamp,
                eventCount: events.count,
                lastEventType: lastEvent.type,
                hasAvailableCheckpoints: hasCheckpoints,
                isInterrupted: isInterrupted,
                recoverySuggestion: suggestion
            )
            candidates.append(candidate)
        }

        return candidates.sorted { $0.lastEventTimestamp > $1.lastEventTimestamp }
    }

    /// Rehydrates ThreadMessage array from the session's JSONL events.
    public func rehydrateMessages(for threadID: UUID) async -> [ThreadMessage] {
        let events = await SessionLogManager.shared.replayEvents(for: threadID)
        var messages: [ThreadMessage] = []

        for event in events {
            switch event.type {
            case .userPrompt:
                let text = event.payload["text"] ?? ""
                messages.append(ThreadMessage(
                    role: .user,
                    content: text,
                    timestamp: event.timestamp,
                    toolCalls: []
                ))
            case .assistantText:
                let text = event.payload["text"] ?? ""
                messages.append(ThreadMessage(
                    role: .agent,
                    content: text,
                    timestamp: event.timestamp,
                    toolCalls: []
                ))
            case .toolResult:
                let tool = event.payload["tool"] ?? "tool"
                let output = event.payload["output"] ?? ""
                let tc = ThreadToolCall(
                    id: event.id,
                    name: tool,
                    arguments: event.payload["command"] ?? "",
                    status: .succeeded(output: output)
                )
                messages.append(ThreadMessage(
                    role: .agent,
                    content: output,
                    timestamp: event.timestamp,
                    toolCalls: [tc]
                ))
            default:
                break
            }
        }

        return messages
    }
}
