// MultiLanguageLSPManager.swift
// AdventurersCore — Multi-Language LSP Discovery & Daemon Multiplexer
// Connects to sourcekit-lsp (Swift/C/C++), rust-analyzer (Rust), zls (Zig), and pyright (Python).

import Foundation

public enum LSPTargetLanguage: String, Sendable, CaseIterable {
    case swift = "swift"
    case rust = "rust"
    case zig = "zig"
    case python = "python"
    case c = "c"
    case cpp = "cpp"

    public var serverBinaryNames: [String] {
        switch self {
        case .swift, .c, .cpp:
            return ["sourcekit-lsp", "/Users/fource/.swiftly/bin/sourcekit-lsp", "/usr/bin/sourcekit-lsp"]
        case .rust:
            return ["rust-analyzer", "/Users/fource/.cargo/bin/rust-analyzer", "/opt/homebrew/bin/rust-analyzer"]
        case .zig:
            return ["zls", "/opt/homebrew/bin/zls", "/usr/local/bin/zls"]
        case .python:
            return ["pyright-langserver", "pyright", "pylsp", "/opt/homebrew/bin/pyright-langserver"]
        }
    }
}

public struct LSPDaemonDescriptor: Sendable, Equatable {
    public let language: LSPTargetLanguage
    public let binaryPath: String
    public let isAvailable: Bool

    public init(language: LSPTargetLanguage, binaryPath: String, isAvailable: Bool) {
        self.language = language
        self.binaryPath = binaryPath
        self.isAvailable = isAvailable
    }
}

public actor MultiLanguageLSPManager {
    public static let shared = MultiLanguageLSPManager()

    public init() {}

    /// Discovers all available LSP server binaries installed on the host machine.
    public func discoverInstalledServers() -> [LSPDaemonDescriptor] {
        var results: [LSPDaemonDescriptor] = []

        for lang in LSPTargetLanguage.allCases {
            var foundPath: String? = nil
            for candidate in lang.serverBinaryNames {
                if candidate.hasPrefix("/") {
                    if FileManager.default.isExecutableFile(atPath: candidate) {
                        foundPath = candidate
                        break
                    }
                } else {
                    // Search in standard PATH
                    let standardPaths = ["/usr/bin", "/usr/local/bin", "/opt/homebrew/bin", "/Users/fource/.cargo/bin", "/Users/fource/.swiftly/bin"]
                    for dir in standardPaths {
                        let full = "\(dir)/\(candidate)"
                        if FileManager.default.isExecutableFile(atPath: full) {
                            foundPath = full
                            break
                        }
                    }
                    if foundPath != nil { break }
                }
            }

            if let path = foundPath {
                results.append(LSPDaemonDescriptor(language: lang, binaryPath: path, isAvailable: true))
            } else {
                results.append(LSPDaemonDescriptor(language: lang, binaryPath: lang.serverBinaryNames[0], isAvailable: false))
            }
        }

        return results
    }

    /// Determines the primary language of a target file or workspace.
    public func detectLanguage(for filePath: String) -> LSPTargetLanguage? {
        let ext = (filePath as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return .swift
        case "rs": return .rust
        case "zig": return .zig
        case "py": return .python
        case "c", "h": return .c
        case "cpp", "cc", "cxx", "hpp": return .cpp
        default: return nil
        }
    }
}
