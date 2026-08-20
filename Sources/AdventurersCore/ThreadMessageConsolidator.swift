// ThreadMessageConsolidator.swift
// Adventurers Harness — Pure Domain Message Compaction & Consolidation Engine

import Foundation

// MARK: - Thread Message Consolidator

/// Consolidates consecutive multi-turn agent messages and close-proximity (same minute/interval) tool call runs
/// into a single sleek compounded card for clean, uncluttered UX both dynamically and retroactively.
public struct ThreadMessageConsolidator: Sendable {
    /// Threshold in seconds for considering separate agent messages part of the same continuous long-horizon run.
    public static let longHorizonMaxIntervalSeconds: TimeInterval = 120.0

    public static func consolidate(_ messages: [ThreadMessage]) -> [ThreadMessage] {
        guard !messages.isEmpty else { return [] }
        var result: [ThreadMessage] = []
        var pendingAgentGroup: [ThreadMessage] = []

        func flushAgentGroup() {
            guard !pendingAgentGroup.isEmpty else { return }
            if pendingAgentGroup.count == 1 {
                result.append(pendingAgentGroup[0])
            } else {
                let first = pendingAgentGroup[0]
                let last = pendingAgentGroup[pendingAgentGroup.count - 1]

                var allToolCalls: [ThreadToolCall] = []
                var allToolResults: [ThreadToolResult] = []
                var thinkingParts: [String] = []
                var contentParts: [String] = []

                for msg in pendingAgentGroup {
                    allToolCalls.append(contentsOf: msg.toolCalls)
                    allToolResults.append(contentsOf: msg.toolResults)
                    if let think = msg.thinkingContent, !think.isEmpty {
                        thinkingParts.append(think)
                    }
                    let trimmed = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)

                    // Filter out transient intermediate noise phrases
                    let isTransientNoise = trimmed.isEmpty
                        || trimmed.hasPrefix("Executed ")
                        || trimmed.hasPrefix("Executing ")
                        || trimmed.hasPrefix("Running ")
                        || trimmed.hasPrefix("<tool_call>")
                        || trimmed.hasPrefix("Tool '")

                    if !isTransientNoise {
                        contentParts.append(trimmed)
                    }
                }

                let finalContent: String
                if let lastMeaningful = contentParts.last, !lastMeaningful.isEmpty {
                    finalContent = lastMeaningful
                } else if !last.content.isEmpty && !last.content.hasPrefix("Executed ") {
                    finalContent = last.content
                } else if !allToolCalls.isEmpty {
                    if pendingAgentGroup.count > 2 || allToolCalls.count > 3 {
                        finalContent = "⚡️ Long-Horizon Run: Completed \(pendingAgentGroup.count) steps with \(allToolCalls.count) tool executions."
                    } else {
                        finalContent = "Executed \(allToolCalls.count) tool\(allToolCalls.count == 1 ? "" : "s")."
                    }
                } else {
                    finalContent = ""
                }

                let mergedThinking = thinkingParts.isEmpty ? nil : thinkingParts.joined(separator: "\n\n")

                let consolidated = ThreadMessage(
                    id: first.id,
                    role: .agent,
                    content: finalContent,
                    timestamp: last.timestamp,
                    toolCalls: allToolCalls,
                    toolResults: allToolResults,
                    isStreaming: last.isStreaming,
                    thinkingContent: mergedThinking
                )
                result.append(consolidated)
            }
            pendingAgentGroup.removeAll()
        }

        for msg in messages {
            if msg.role == .agent {
                if let lastInGroup = pendingAgentGroup.last {
                    // Check time proximity (same minute or within max interval)
                    let delta = abs(msg.timestamp.timeIntervalSince(lastInGroup.timestamp))
                    let calendar = Calendar.current
                    let sameMinute = calendar.isDate(msg.timestamp, equalTo: lastInGroup.timestamp, toGranularity: .minute)

                    if sameMinute || delta <= longHorizonMaxIntervalSeconds {
                        pendingAgentGroup.append(msg)
                    } else {
                        // Flushes previous long-horizon run before starting a separated turn
                        flushAgentGroup()
                        pendingAgentGroup.append(msg)
                    }
                } else {
                    pendingAgentGroup.append(msg)
                }
            } else {
                flushAgentGroup()
                result.append(msg)
            }
        }
        flushAgentGroup()
        return result
    }
}
