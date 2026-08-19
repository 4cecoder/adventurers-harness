// AdventurersCore - Pure Swift Checkpoint Disk Persistence & Rollback Engine
// Inspired by Muse's tbh_event::retention::LiveRetainedEventLog
// Persists atomic file snapshots and rollback states to ~/.adventurers/checkpoints/{sessionID}/

import Foundation

public actor CheckpointPersistence {
    public static let shared = CheckpointPersistence()

    private let fileManager = FileManager.default

    public init() {}

    /// Base checkpoints directory: ~/.adventurers/checkpoints/
    public var baseDirectory: URL {
        let home = fileManager.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".adventurers", isDirectory: true)
                   .appendingPathComponent("checkpoints", isDirectory: true)
    }

    private func ensureBaseDirectory() {
        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    public func checkpointDirectory(for sessionID: UUID) -> URL {
        return baseDirectory.appendingPathComponent(sessionID.uuidString, isDirectory: true)
    }

    /// Saves a session checkpoint to disk.
    public func saveCheckpoint(_ checkpoint: SessionCheckpoint, sessionID: UUID) throws {
        let sessionDir = checkpointDirectory(for: sessionID)
        try fileManager.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        let fileURL = sessionDir.appendingPathComponent("\(checkpoint.id.uuidString).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(checkpoint)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Loads all persisted checkpoints for a session, ordered chronologically.
    public func loadCheckpoints(for sessionID: UUID) -> [SessionCheckpoint] {
        let sessionDir = checkpointDirectory(for: sessionID)
        guard let fileURLs = try? fileManager.contentsOfDirectory(at: sessionDir, includingPropertiesForKeys: nil) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var result: [SessionCheckpoint] = []
        for url in fileURLs where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let checkpoint = try? decoder.decode(SessionCheckpoint.self, from: data) else {
                continue
            }
            result.append(checkpoint)
        }

        return result.sorted { $0.timestamp < $1.timestamp }
    }

    /// Restores all files in a checkpoint back to disk atomically in the target workspace.
    public func rollbackToDiskCheckpoint(
        checkpoint: SessionCheckpoint,
        workspacePath: String
    ) throws -> [String] {
        var restoredFiles: [String] = []

        for snapshot in checkpoint.snapshots {
            let targetURL = URL(fileURLWithPath: workspacePath).appendingPathComponent(snapshot.relativePath)
            let parentDir = targetURL.deletingLastPathComponent()

            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
            guard let data = snapshot.content.data(using: .utf8) else { continue }
            try data.write(to: targetURL, options: .atomic)
            restoredFiles.append(snapshot.relativePath)
        }

        return restoredFiles
    }

    /// Removes all checkpoints for a session.
    public func deleteCheckpoints(for sessionID: UUID) throws {
        let sessionDir = checkpointDirectory(for: sessionID)
        if fileManager.fileExists(atPath: sessionDir.path) {
            try fileManager.removeItem(at: sessionDir)
        }
    }
}
