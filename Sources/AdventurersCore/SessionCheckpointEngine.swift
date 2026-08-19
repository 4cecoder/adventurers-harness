// AdventurersCore - Pure Swift Session Checkpoint & Rollback Engine
// Provides atomic snapshotting, change-tracking, and 1-click rollback for long-horizon agent runs.

import Foundation

// MARK: - Checkpoint Models

public struct FileSnapshot: Sendable, Codable, Identifiable {
    public var id: String { relativePath }
    public let relativePath: String
    public let content: String
    public let fileSizeBytes: Int
    public let timestamp: Date

    public init(relativePath: String, content: String, fileSizeBytes: Int, timestamp: Date = Date()) {
        self.relativePath = relativePath
        self.content = content
        self.fileSizeBytes = fileSizeBytes
        self.timestamp = timestamp
    }
}

public struct SessionCheckpoint: Sendable, Codable, Identifiable {
    public let id: UUID
    public let turnNumber: Int
    public let timestamp: Date
    public let summary: String
    public let snapshots: [FileSnapshot]
    public let affectedFiles: [String]

    public init(
        id: UUID = UUID(),
        turnNumber: Int,
        timestamp: Date = Date(),
        summary: String,
        snapshots: [FileSnapshot],
        affectedFiles: [String]
    ) {
        self.id = id
        self.turnNumber = turnNumber
        self.timestamp = timestamp
        self.summary = summary
        self.snapshots = snapshots
        self.affectedFiles = affectedFiles
    }

    public var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: timestamp)
    }
}

// MARK: - Checkpoint Engine

public actor SessionCheckpointEngine {
    public static let shared = SessionCheckpointEngine()

    private var checkpoints: [UUID: [SessionCheckpoint]] = [:] // SessionID -> Checkpoints

    public init() {}

    /// Takes an atomic snapshot of modified or target files prior to a tool run.
    public func createCheckpoint(
        sessionID: UUID,
        turnNumber: Int,
        summary: String,
        workspacePath: String,
        targetFiles: [String]
    ) async -> SessionCheckpoint {
        var snapshots: [FileSnapshot] = []
        let fm = FileManager.default

        for file in targetFiles {
            let fullPath = (workspacePath as NSString).appendingPathComponent(file)
            if fm.fileExists(atPath: fullPath), let data = try? Data(contentsOf: URL(fileURLWithPath: fullPath)),
               let str = String(data: data, encoding: .utf8) {
                snapshots.append(FileSnapshot(relativePath: file, content: str, fileSizeBytes: data.count))
            }
        }

        let checkpoint = SessionCheckpoint(
            turnNumber: turnNumber,
            summary: summary,
            snapshots: snapshots,
            affectedFiles: targetFiles
        )

        var list = checkpoints[sessionID] ?? []
        list.append(checkpoint)
        checkpoints[sessionID] = list

        return checkpoint
    }

    /// Retrieves all checkpoints for a given session.
    public func getCheckpoints(for sessionID: UUID) -> [SessionCheckpoint] {
        return checkpoints[sessionID] ?? []
    }

    /// Rolls back the workspace to the specified checkpoint.
    public func rollback(
        sessionID: UUID,
        checkpointID: UUID,
        workspacePath: String
    ) throws -> [String] {
        guard let list = checkpoints[sessionID],
              let target = list.first(where: { $0.id == checkpointID }) else {
            throw CheckpointError.checkpointNotFound
        }

        var restoredFiles: [String] = []

        for snapshot in target.snapshots {
            let fullPath = (workspacePath as NSString).appendingPathComponent(snapshot.relativePath)
            let fileURL = URL(fileURLWithPath: fullPath)

            // Ensure parent dir exists
            let parent = fileURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

            guard let data = snapshot.content.data(using: .utf8) else {
                continue
            }
            try data.write(to: fileURL)
            restoredFiles.append(snapshot.relativePath)
        }

        return restoredFiles
    }

    /// Clears all checkpoints for a completed or deleted session.
    public func clear(sessionID: UUID) {
        checkpoints.removeValue(forKey: sessionID)
    }
}

public enum CheckpointError: Error, LocalizedError, Sendable {
    case checkpointNotFound
    case restoreFailed(String)

    public var errorDescription: String? {
        switch self {
        case .checkpointNotFound:
            return "Checkpoint not found in session registry."
        case .restoreFailed(let msg):
            return "Rollback failed: \(msg)"
        }
    }
}
