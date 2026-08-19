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

        // Automatically persist checkpoint to disk for crash durability
        try? await CheckpointPersistence.shared.saveCheckpoint(checkpoint, sessionID: sessionID)

        return checkpoint
    }

    /// Retrieves all checkpoints for a given session, combining in-memory and disk records.
    public func getCheckpoints(for sessionID: UUID) async -> [SessionCheckpoint] {
        if let memList = checkpoints[sessionID], !memList.isEmpty {
            return memList
        }
        let diskList = await CheckpointPersistence.shared.loadCheckpoints(for: sessionID)
        checkpoints[sessionID] = diskList
        return diskList
    }

    /// Rolls back the workspace to the specified checkpoint.
    public func rollback(
        sessionID: UUID,
        checkpointID: UUID,
        workspacePath: String
    ) async throws -> [String] {
        let list = await getCheckpoints(for: sessionID)
        guard let target = list.first(where: { $0.id == checkpointID }) else {
            throw CheckpointError.checkpointNotFound
        }

        return try await CheckpointPersistence.shared.rollbackToDiskCheckpoint(
            checkpoint: target,
            workspacePath: workspacePath
        )
    }

    /// Clears all checkpoints for a completed or deleted session.
    public func clear(sessionID: UUID) async {
        checkpoints.removeValue(forKey: sessionID)
        try? await CheckpointPersistence.shared.deleteCheckpoints(for: sessionID)
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
