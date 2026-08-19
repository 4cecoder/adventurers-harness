// AdventurersCore - Pure Swift Append-Only JSONL Session Logging
// Inspired by Muse's tbh_event::jsonl::JsonlEventLogStorage
// Provides indestructible event streaming to ~/.adventurers/sessions/{threadID}.jsonl

import Foundation

// MARK: - Event Types

public enum SessionEventType: String, Codable, Sendable {
    case sessionStarted = "session_started"
    case userPrompt = "user_prompt"
    case thought = "thought"
    case assistantText = "assistant_text"
    case toolCall = "tool_call"
    case toolResult = "tool_result"
    case gateCertification = "gate_certification"
    case checkpointCreated = "checkpoint_created"
    case checkpointRestored = "checkpoint_restored"
    case diffApplied = "diff_applied"
    case error = "error"
    case sessionTerminated = "session_terminated"
}

// MARK: - Session Event Record

public struct SessionEvent: Codable, Identifiable, Sendable {
    public let id: String
    public let timestamp: Date
    public let threadID: UUID
    public let type: SessionEventType
    public let turnIndex: Int
    public let payload: [String: String]
    public let tokenCount: Int?

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        threadID: UUID,
        type: SessionEventType,
        turnIndex: Int = 0,
        payload: [String: String] = [:],
        tokenCount: Int? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.threadID = threadID
        self.type = type
        self.turnIndex = turnIndex
        self.payload = payload
        self.tokenCount = tokenCount
    }
}

// MARK: - Session Log Manager

public actor SessionLogManager {
    public static let shared = SessionLogManager()

    private let fileManager = FileManager.default
    private var openFileHandles: [UUID: FileHandle] = [:]

    public init() {}

    /// Default base directory for persistent JSONL logs: ~/.adventurers/sessions/
    public var sessionsDirectory: URL {
        let home = fileManager.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".adventurers", isDirectory: true)
                   .appendingPathComponent("sessions", isDirectory: true)
    }

    private func ensureStorageDirectory() {
        try? fileManager.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    }

    public func logFilePath(for threadID: UUID) -> URL {
        return sessionsDirectory.appendingPathComponent("\(threadID.uuidString).jsonl")
    }

    /// Appends a single structured event directly to disk in append-only JSONL format.
    public func appendEvent(_ event: SessionEvent) {
        ensureStorageDirectory()
        let fileURL = logFilePath(for: event.threadID)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = []

        guard let eventData = try? encoder.encode(event) else { return }
        var lineData = eventData
        lineData.append(0x0A) // \n newline

        do {
            if !fileManager.fileExists(atPath: fileURL.path) {
                try lineData.write(to: fileURL, options: .atomic)
            } else {
                let fileHandle: FileHandle
                if let existing = openFileHandles[event.threadID] {
                    fileHandle = existing
                } else {
                    fileHandle = try FileHandle(forWritingTo: fileURL)
                    openFileHandles[event.threadID] = fileHandle
                }
                try fileHandle.seekToEnd()
                try fileHandle.write(contentsOf: lineData)
                try fileHandle.synchronize() // Force flush to disk
            }
        } catch {
            print("[SessionLog] Error appending event to disk: \(error.localizedDescription)")
        }
    }

    /// Replays all events from the JSONL log on disk.
    public func replayEvents(for threadID: UUID) -> [SessionEvent] {
        let fileURL = logFilePath(for: threadID)
        guard let fileData = try? Data(contentsOf: fileURL),
              let contentString = String(data: fileData, encoding: .utf8) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var events: [SessionEvent] = []
        let lines = contentString.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let lineData = trimmed.data(using: .utf8) else { continue }
            if let event = try? decoder.decode(SessionEvent.self, from: lineData) {
                events.append(event)
            }
        }

        return events
    }

    /// Lists all existing session IDs with available JSONL logs on disk.
    public func listSavedSessionIDs() -> [UUID] {
        guard let files = try? fileManager.contentsOfDirectory(at: sessionsDirectory, includingPropertiesForKeys: nil) else {
            return []
        }

        return files.compactMap { url in
            guard url.pathExtension == "jsonl" else { return nil }
            let uuidStr = url.deletingPathExtension().lastPathComponent
            return UUID(uuidString: uuidStr)
        }
    }

    /// Closes and flushes open file handles.
    public func closeLog(for threadID: UUID) {
        if let handle = openFileHandles.removeValue(forKey: threadID) {
            try? handle.synchronize()
            try? handle.close()
        }
    }

    /// Exports full conversation log as clean markdown.
    public func exportMarkdownTranscript(for threadID: UUID) -> String {
        let events = replayEvents(for: threadID)
        guard !events.isEmpty else { return "# Session Log: \(threadID)\n\n*No events recorded.*" }

        var md = "# Adventurers Session Transcript\n"
        md += "**Thread ID:** `\(threadID.uuidString)`  \n"
        md += "**Events Recorded:** \(events.count)  \n\n---\n\n"

        for event in events {
            let timeStr = DateFormatter.localizedString(from: event.timestamp, dateStyle: .none, timeStyle: .medium)
            switch event.type {
            case .userPrompt:
                md += "### 👤 User (\(timeStr))\n\(event.payload["text"] ?? "")\n\n"
            case .assistantText:
                md += "### 🤖 Assistant (\(timeStr))\n\(event.payload["text"] ?? "")\n\n"
            case .thought:
                md += "> 🧠 **Thinking:** \(event.payload["thought"] ?? "")\n\n"
            case .toolCall:
                md += "⚙️ **Tool Call:** `\(event.payload["tool"] ?? "unknown")`\n```bash\n\(event.payload["command"] ?? event.payload["arguments"] ?? "")\n```\n\n"
            case .toolResult:
                md += "📋 **Tool Result:**\n```\n\(event.payload["output"] ?? "")\n```\n\n"
            case .gateCertification:
                md += "🛡️ **Gate Certified:** `\(event.payload["gate"] ?? "")` (\(event.payload["status"] ?? "PASSED"))\n\n"
            case .checkpointCreated:
                md += "💾 **Checkpoint Created:** \(event.payload["summary"] ?? "")\n\n"
            case .checkpointRestored:
                md += "⏪ **Checkpoint Restored:** \(event.payload["summary"] ?? "")\n\n"
            case .diffApplied:
                md += "📝 **Diff Applied:** `\(event.payload["file"] ?? "")`\n\n"
            case .error:
                md += "⚠️ **Error:** \(event.payload["message"] ?? "")\n\n"
            default:
                break
            }
        }

        return md
    }
}
