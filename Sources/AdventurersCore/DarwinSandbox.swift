// AdventurersCore - Darwin Seatbelt Sandbox Engine
// Implements Apple's kernel sandbox profiles in pure Swift 6

import Foundation
import Darwin

// MARK: - Sandbox Mode

public enum SandboxMode: Sendable, Equatable {
    /// Read-only inspection of the filesystem; zero write permissions.
    case readOnly
    /// Restricted write access locked strictly to the workspace root directory.
    case workspaceWrite(workspaceRoot: URL, additionalAllowedRoots: [URL] = [])
    /// Unrestricted access (requires explicit user confirmation).
    case dangerFullAccess

    public var displayName: String {
        switch self {
        case .readOnly: return "Read-Only"
        case .workspaceWrite: return "Workspace-Write"
        case .dangerFullAccess: return "Full System Access"
        }
    }
}

// MARK: - Darwin Sandbox Engine

public actor DarwinSandbox {
    public static let shared = DarwinSandbox()

    private init() {}

    /// Generates a Darwin Seatbelt Scheme profile for the specified sandbox mode.
    public func generateSeatbeltProfile(for mode: SandboxMode) -> String {
        switch mode {
        case .readOnly:
            return """
            (version 1)
            (deny default)
            (allow process-exec)
            (allow process-fork)
            (allow sysctl-read)
            (allow file-read*)
            (allow system-socket (socket-domain AF_UNIX))
            (allow network-bind (local unix-socket))
            (allow network-outbound (remote unix-socket))
            """

        case .workspaceWrite(let root, let extraRoots):
            var writableSubpaths = [root.path]
            writableSubpaths.append(contentsOf: extraRoots.map(\.path))
            
            let allowedWrites = writableSubpaths.map { path in
                "(allow file-write* (subpath \"\(path)\"))"
            }.joined(separator: "\n")

            return """
            (version 1)
            (deny default)
            (allow process-exec)
            (allow process-fork)
            (allow sysctl-read)
            (allow file-read*)
            (allow system-socket (socket-domain AF_UNIX))
            (allow network-bind (local unix-socket))
            (allow network-outbound (remote unix-socket))
            \(allowedWrites)
            (allow file-write* (subpath "/private/tmp"))
            (allow file-write* (subpath "/var/folders"))
            """

        case .dangerFullAccess:
            return """
            (version 1)
            (allow default)
            """
        }
    }

    /// Validates whether a file path modification is permitted under the current mode.
    public func validatePathAccess(targetPath: String, mode: SandboxMode) -> Bool {
        let standardPath = (targetPath as NSString).standardizingPath

        switch mode {
        case .readOnly:
            return false

        case .workspaceWrite(let root, let extraRoots):
            let canonicalRoot = (root.path as NSString).standardizingPath
            if standardPath.hasPrefix(canonicalRoot) {
                return true
            }
            for extra in extraRoots {
                let canonicalExtra = (extra.path as NSString).standardizingPath
                if standardPath.hasPrefix(canonicalExtra) {
                    return true
                }
            }
            // Allow temporary directories for scratch operations
            if standardPath.hasPrefix("/tmp") || standardPath.hasPrefix("/private/tmp") || standardPath.hasPrefix("/var/folders") {
                return true
            }
            return false

        case .dangerFullAccess:
            return true
        }
    }
}
