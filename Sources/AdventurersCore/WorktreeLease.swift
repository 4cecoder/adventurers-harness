// AdventurersCore - Worktree Lease & Multi-Agent Isolation Manager
// Implements lease-based ownership preventing concurrent access to git worktrees or workspace subdirectories.

import Foundation

public struct WorktreeLease: Sendable, Identifiable, Codable, Equatable {
    public let id: UUID
    public let workspacePath: String
    public let ownerThreadID: UUID
    public let acquiredAt: Date
    public let expiresAt: Date
    public let purpose: String

    public var isExpired: Bool {
        Date() > expiresAt
    }

    public init(
        id: UUID = UUID(),
        workspacePath: String,
        ownerThreadID: UUID,
        durationSeconds: TimeInterval = 300, // 5 minutes default lease
        purpose: String
    ) {
        self.id = id
        self.workspacePath = workspacePath
        self.ownerThreadID = ownerThreadID
        self.acquiredAt = Date()
        self.expiresAt = Date().addingTimeInterval(durationSeconds)
        self.purpose = purpose
    }
}

public enum LeaseAcquisitionResult: Sendable, Equatable {
    case acquired(lease: WorktreeLease)
    case denied(existingLease: WorktreeLease, remainingSeconds: TimeInterval)
}

public actor WorktreeLeaseManager {
    public static let shared = WorktreeLeaseManager()

    // Keyed by normalized workspace absolute path
    private var activeLeases: [String: WorktreeLease] = [:]
    private let lock = NSLock()

    public init() {}

    /// Normalizes path for dictionary keying.
    private func normalizePath(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardized.path
    }

    /// Attempts to acquire an exclusive lease on a worktree or workspace directory.
    public func acquireLease(
        workspacePath: String,
        ownerThreadID: UUID,
        durationSeconds: TimeInterval = 300,
        purpose: String
    ) -> LeaseAcquisitionResult {
        let norm = normalizePath(workspacePath)

        // Clean up expired leases
        if let current = activeLeases[norm], current.isExpired {
            activeLeases.removeValue(forKey: norm)
        }

        // Check for existing unexpired lease
        if let current = activeLeases[norm] {
            if current.ownerThreadID == ownerThreadID {
                // Renew lease for same owner
                let renewed = WorktreeLease(
                    id: current.id,
                    workspacePath: norm,
                    ownerThreadID: ownerThreadID,
                    durationSeconds: durationSeconds,
                    purpose: purpose
                )
                activeLeases[norm] = renewed
                return .acquired(lease: renewed)
            } else {
                let remaining = max(0, current.expiresAt.timeIntervalSince(Date()))
                return .denied(existingLease: current, remainingSeconds: remaining)
            }
        }

        let newLease = WorktreeLease(
            workspacePath: norm,
            ownerThreadID: ownerThreadID,
            durationSeconds: durationSeconds,
            purpose: purpose
        )
        activeLeases[norm] = newLease
        return .acquired(lease: newLease)
    }

    /// Releases an existing lease owned by the thread.
    public func releaseLease(workspacePath: String, ownerThreadID: UUID) -> Bool {
        let norm = normalizePath(workspacePath)
        guard let lease = activeLeases[norm], lease.ownerThreadID == ownerThreadID else {
            return false
        }
        activeLeases.removeValue(forKey: norm)
        return true
    }

    /// Checks if a directory is currently locked by a foreign thread.
    public func isLockedByOther(workspacePath: String, currentThreadID: UUID) -> Bool {
        let norm = normalizePath(workspacePath)
        guard let lease = activeLeases[norm], !lease.isExpired else {
            return false
        }
        return lease.ownerThreadID != currentThreadID
    }

    /// Returns all currently active leases.
    public func allActiveLeases() -> [WorktreeLease] {
        let now = Date()
        return activeLeases.values.filter { $0.expiresAt > now }
    }
}
