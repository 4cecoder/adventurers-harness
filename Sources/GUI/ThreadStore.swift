// AdventurersHarness - ThreadStore
// Persistent CRUD and Archival System for Agent Threads and Message Trajectories

import Foundation
import SwiftUI
import AdventurersCore

// MARK: - Persisted Domain Models

public struct PersistedThreadData: Codable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var status: String
    public var summary: String
    public var lastActivity: Date
    public var createdAt: Date
    public var agentName: String
    public var selectedModel: String
    public var isArchived: Bool
    public var isPinned: Bool
    public var workingDirectory: String?
    public var messages: [PersistedThreadMessage]

    public init(
        id: UUID = UUID(),
        name: String,
        status: String = "running",
        summary: String = "",
        lastActivity: Date = .now,
        createdAt: Date = .now,
        agentName: String = "Adventurer",
        selectedModel: String = "mimo-v2.5",
        isArchived: Bool = false,
        isPinned: Bool = false,
        workingDirectory: String? = nil,
        messages: [PersistedThreadMessage] = []
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.summary = summary
        self.lastActivity = lastActivity
        self.createdAt = createdAt
        self.agentName = agentName
        self.selectedModel = selectedModel
        self.isArchived = isArchived
        self.isPinned = isPinned
        self.workingDirectory = workingDirectory
        self.messages = messages
    }
}

public struct PersistedThreadMessage: Codable, Sendable, Identifiable {
    public let id: String
    public var role: String
    public var content: String
    public var timestamp: Date
    public var thinkingContent: String?
    public var toolCalls: [PersistedToolCallData]
    public var toolResults: [PersistedToolResultData]

    public init(
        id: String = UUID().uuidString,
        role: String,
        content: String,
        timestamp: Date = .now,
        thinkingContent: String? = nil,
        toolCalls: [PersistedToolCallData] = [],
        toolResults: [PersistedToolResultData] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.thinkingContent = thinkingContent
        self.toolCalls = toolCalls
        self.toolResults = toolResults
    }
}

public struct PersistedToolCallData: Codable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public var arguments: String
    public var status: String
    public var output: String?
    public var error: String?

    public init(
        id: String = UUID().uuidString,
        name: String,
        arguments: String,
        status: String = "pending",
        output: String? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.status = status
        self.output = output
        self.error = error
    }
}

public struct PersistedToolResultData: Codable, Sendable, Identifiable {
    public let id: String
    public var toolCallID: String
    public var output: String
    public var isError: Bool

    public init(id: String = UUID().uuidString, toolCallID: String, output: String, isError: Bool = false) {
        self.id = id
        self.toolCallID = toolCallID
        self.output = output
        self.isError = isError
    }
}

// MARK: - ThreadStore Manager

@MainActor
public final class ThreadStore: Sendable {
    public static let shared = ThreadStore()

    private let fileManager = FileManager.default
    private var threadsDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AdventurersHarness/threads")
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var indexFileURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AdventurersHarness")
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("threads_index.json")
    }

    // MARK: - CRUD Operations

    /// Save or update a thread along with its message history
    public func saveThread(
        item: ThreadItem,
        messages: [ThreadMessage],
        selectedModel: String = "mimo-v2.5"
    ) {
        let persistedMessages = messages.map { msg -> PersistedThreadMessage in
            let calls = msg.toolCalls.map { tc -> PersistedToolCallData in
                let statusStr: String
                var out: String? = nil
                var err: String? = nil
                switch tc.status {
                case .pending: statusStr = "pending"
                case .running: statusStr = "running"
                case .succeeded(let o):
                    statusStr = "succeeded"
                    out = o
                case .failed(let e):
                    statusStr = "failed"
                    err = e
                }
                return PersistedToolCallData(
                    id: tc.id,
                    name: tc.name,
                    arguments: tc.arguments,
                    status: statusStr,
                    output: out,
                    error: err
                )
            }

            let results = msg.toolResults.map { tr in
                PersistedToolResultData(
                    id: tr.id,
                    toolCallID: tr.toolCallID,
                    output: tr.output,
                    isError: tr.isError
                )
            }

            let roleStr: String
            switch msg.role {
            case .user: roleStr = "user"
            case .agent: roleStr = "agent"
            case .system: roleStr = "system"
            case .gateResult: roleStr = "gateResult"
            }

            return PersistedThreadMessage(
                id: msg.id,
                role: roleStr,
                content: msg.content,
                timestamp: msg.timestamp,
                thinkingContent: msg.thinkingContent,
                toolCalls: calls,
                toolResults: results
            )
        }

        let threadData = PersistedThreadData(
            id: item.id,
            name: item.name,
            status: item.status.rawValue,
            summary: item.summary,
            lastActivity: item.lastActivity,
            createdAt: item.createdAt,
            agentName: item.agentName,
            selectedModel: selectedModel,
            isArchived: item.isArchived,
            isPinned: item.isPinned,
            workingDirectory: item.workingDirectory,
            messages: persistedMessages
        )

        let fileURL = threadsDirectory.appendingPathComponent("\(item.id.uuidString).json")
        if let encoded = try? JSONEncoder().encode(threadData) {
            try? encoded.write(to: fileURL)
        }

        updateIndex()
    }

    /// Load all stored threads (metadata only or full records)
    public func loadAllThreads() -> [ThreadItem] {
        guard let files = try? fileManager.contentsOfDirectory(at: threadsDirectory, includingPropertiesForKeys: nil) else {
            return []
        }

        var items: [ThreadItem] = []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let threadData = try? JSONDecoder().decode(PersistedThreadData.self, from: data) {
                let status = ThreadStatus(rawValue: threadData.status) ?? .running
                let rawDir = threadData.workingDirectory
                let validDir = (rawDir != nil && rawDir != "/" && !rawDir!.isEmpty) ? rawDir! : WorkspaceConfig.defaultWorkspacePath
                let item = ThreadItem(
                    id: threadData.id,
                    name: threadData.name,
                    status: status,
                    summary: threadData.summary,
                    lastActivity: threadData.lastActivity,
                    createdAt: threadData.createdAt,
                    agentName: threadData.agentName,
                    isArchived: threadData.isArchived,
                    isPinned: threadData.isPinned,
                    workingDirectory: validDir
                )
                items.append(item)
            }
        }

        return items.sorted {
            if $0.isPinned != $1.isPinned {
                return $0.isPinned && !$1.isPinned
            }
            return $0.lastActivity > $1.lastActivity
        }
    }

    /// Load full messages for a specific thread ID
    public func loadMessages(for threadID: UUID) -> [ThreadMessage] {
        let fileURL = threadsDirectory.appendingPathComponent("\(threadID.uuidString).json")
        guard let data = try? Data(contentsOf: fileURL),
              let threadData = try? JSONDecoder().decode(PersistedThreadData.self, from: data) else {
            return []
        }

        let loadedMessages = threadData.messages.map { pMsg in
            let role: ThreadMessage.MessageRole
            switch pMsg.role {
            case "user": role = .user
            case "agent": role = .agent
            case "system": role = .system
            case "gateResult": role = .gateResult
            default: role = .agent
            }

            let toolCalls = pMsg.toolCalls.map { tc -> ThreadToolCall in
                let status: ThreadToolCall.ToolCallStatus
                switch tc.status {
                case "succeeded":
                    status = .succeeded(output: tc.output ?? "")
                case "failed":
                    status = .failed(error: tc.error ?? "Failed")
                case "running", "pending":
                    // Historical persisted tool calls from completed sessions should be resolved
                    if let err = tc.error, !err.isEmpty {
                        status = .failed(error: err)
                    } else {
                        status = .succeeded(output: tc.output ?? "")
                    }
                default:
                    status = .succeeded(output: tc.output ?? "")
                }
                return ThreadToolCall(
                    id: tc.id,
                    name: tc.name,
                    arguments: tc.arguments,
                    status: status
                )
            }

            let toolResults = pMsg.toolResults.map { tr in
                ThreadToolResult(
                    id: tr.id,
                    toolCallID: tr.toolCallID,
                    output: tr.output,
                    isError: tr.isError
                )
            }

            return ThreadMessage(
                id: pMsg.id,
                role: role,
                content: pMsg.content,
                timestamp: pMsg.timestamp,
                toolCalls: toolCalls,
                toolResults: toolResults,
                isStreaming: false,
                thinkingContent: pMsg.thinkingContent
            )
        }

        // Retroactively consolidate consecutive multi-turn tool-calling agent messages
        return ThreadMessageConsolidator.consolidate(loadedMessages)
    }

    /// Delete a thread permanently from disk
    public func deleteThread(id: UUID) {
        let fileURL = threadsDirectory.appendingPathComponent("\(id.uuidString).json")
        try? fileManager.removeItem(at: fileURL)
        updateIndex()
    }

    /// Archive or Unarchive a thread
    public func setArchived(id: UUID, isArchived: Bool) {
        let fileURL = threadsDirectory.appendingPathComponent("\(id.uuidString).json")
        guard let data = try? Data(contentsOf: fileURL),
              var threadData = try? JSONDecoder().decode(PersistedThreadData.self, from: data) else {
            return
        }
        threadData.isArchived = isArchived
        threadData.status = isArchived ? "completed" : "running"
        if let encoded = try? JSONEncoder().encode(threadData) {
            try? encoded.write(to: fileURL)
        }
        updateIndex()
    }

    /// Pin or Unpin a thread
    public func setPinned(id: UUID, isPinned: Bool) {
        let fileURL = threadsDirectory.appendingPathComponent("\(id.uuidString).json")
        guard let data = try? Data(contentsOf: fileURL),
              var threadData = try? JSONDecoder().decode(PersistedThreadData.self, from: data) else {
            return
        }
        threadData.isPinned = isPinned
        if let encoded = try? JSONEncoder().encode(threadData) {
            try? encoded.write(to: fileURL)
        }
        updateIndex()
    }

    /// Rename a thread
    public func renameThread(id: UUID, newName: String) {
        let fileURL = threadsDirectory.appendingPathComponent("\(id.uuidString).json")
        guard let data = try? Data(contentsOf: fileURL),
              var threadData = try? JSONDecoder().decode(PersistedThreadData.self, from: data) else {
            return
        }
        threadData.name = newName
        if let encoded = try? JSONEncoder().encode(threadData) {
            try? encoded.write(to: fileURL)
        }
        updateIndex()
    }

    /// Update working directory for a thread
    public func updateWorkingDirectory(id: UUID, workingDirectory: String) {
        let fileURL = threadsDirectory.appendingPathComponent("\(id.uuidString).json")
        guard let data = try? Data(contentsOf: fileURL),
              var threadData = try? JSONDecoder().decode(PersistedThreadData.self, from: data) else {
            return
        }
        threadData.workingDirectory = workingDirectory
        if let encoded = try? JSONEncoder().encode(threadData) {
            try? encoded.write(to: fileURL)
        }
        updateIndex()
    }

    /// Duplicate a thread
    public func duplicateThread(id: UUID) -> ThreadItem? {
        let fileURL = threadsDirectory.appendingPathComponent("\(id.uuidString).json")
        guard let data = try? Data(contentsOf: fileURL),
              let threadData = try? JSONDecoder().decode(PersistedThreadData.self, from: data) else {
            return nil
        }

        let newID = UUID()
        let newName = "\(threadData.name) (Copy)"
        let newThread = PersistedThreadData(
            id: newID,
            name: newName,
            status: "running",
            summary: threadData.summary,
            lastActivity: .now,
            createdAt: .now,
            agentName: threadData.agentName,
            selectedModel: threadData.selectedModel,
            isArchived: false,
            isPinned: false,
            messages: threadData.messages
        )

        let newURL = threadsDirectory.appendingPathComponent("\(newID.uuidString).json")
        if let encoded = try? JSONEncoder().encode(newThread) {
            try? encoded.write(to: newURL)
        }
        updateIndex()

        return ThreadItem(
            id: newID,
            name: newName,
            status: .running,
            summary: threadData.summary,
            lastActivity: .now,
            createdAt: .now,
            agentName: threadData.agentName,
            isArchived: false,
            isPinned: false
        )
    }

    /// Clear all archived threads
    public func clearArchivedThreads() {
        guard let files = try? fileManager.contentsOfDirectory(at: threadsDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let threadData = try? JSONDecoder().decode(PersistedThreadData.self, from: data),
               threadData.isArchived {
                try? fileManager.removeItem(at: file)
            }
        }
        updateIndex()
    }

    /// Export thread to Markdown transcript
    public func exportMarkdown(for thread: ThreadItem, messages: [ThreadMessage]) -> String {
        var doc = "# Adventure Thread: \(thread.name)\n"
        doc += "**Created:** \(thread.createdAt.formatted(date: .abbreviated, time: .shortened))\n"
        doc += "**Status:** \(thread.status.label)\n"
        doc += "**Agent:** \(thread.agentName)\n"
        doc += "---\n\n"

        for msg in messages {
            let roleHeader = msg.role == .user ? "### 👤 User" : (msg.role == .agent ? "### 🤖 Agent (\(thread.agentName))" : "### ⚙️ System")
            doc += "\(roleHeader)\n"
            if let thinking = msg.thinkingContent, !thinking.isEmpty {
                doc += "> *Thinking Process:*\n"
                doc += "> " + thinking.replacingOccurrences(of: "\n", with: "\n> ") + "\n\n"
            }
            doc += "\(msg.content)\n\n"

            for tc in msg.toolCalls {
                doc += "```bash\n# Tool Call: \(tc.name)\n\(tc.arguments)\n```\n\n"
            }
            for tr in msg.toolResults {
                doc += "```output\n# Tool Output:\n\(tr.output)\n```\n\n"
            }
            doc += "---\n\n"
        }

        return doc
    }

    private func updateIndex() {
        // Keeps index file up to date for fast reads
        let threads = loadAllThreads()
        if let data = try? JSONEncoder().encode(threads.map { $0.id.uuidString }) {
            try? data.write(to: indexFileURL)
        }
    }
}
