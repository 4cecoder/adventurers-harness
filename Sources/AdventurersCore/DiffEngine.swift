// AdventurersCore - Pure Swift Streaming Patch & Diff Engine
// Implements preflight validation, hunk matching, and atomic rollbacks

import Foundation

// MARK: - Diff Models

public struct DiffHunk: Sendable, Identifiable {
    public let id = UUID()
    public let oldStart: Int
    public let oldCount: Int
    public let newStart: Int
    public let newCount: Int
    public let lines: [DiffLine]

    public init(oldStart: Int, oldCount: Int, newStart: Int, newCount: Int, lines: [DiffLine]) {
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.lines = lines
    }
}

public struct DiffLine: Sendable, Identifiable {
    public let id = UUID()
    public enum Kind: Sendable {
        case context
        case addition
        case deletion
    }
    public let kind: Kind
    public let text: String

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }
}

public struct FilePatch: Sendable, Identifiable {
    public let id = UUID()
    public let filePath: String
    public let hunks: [DiffHunk]

    public init(filePath: String, hunks: [DiffHunk]) {
        self.filePath = filePath
        self.hunks = hunks
    }
}

// MARK: - Preflight Check Result

public enum PreflightResult: Sendable {
    case ready
    case conflict(reason: String, line: Int)
}

// MARK: - Diff Engine

public final class DiffEngine: Sendable {
    public static let shared = DiffEngine()

    public init() {}

    /// Parses a raw unified diff string into structured FilePatch models.
    public func parseUnifiedDiff(_ rawDiff: String) -> [FilePatch] {
        var patches: [FilePatch] = []
        var currentFile: String?
        var currentHunks: [DiffHunk] = []
        var currentLines: [DiffLine] = []
        var currentOldStart = 0
        var currentOldCount = 0
        var currentNewStart = 0
        var currentNewCount = 0

        let lines = rawDiff.components(separatedBy: .newlines)

        for line in lines {
            if line.hasPrefix("+++ b/") || line.hasPrefix("+++ ") {
                if let file = currentFile {
                    if !currentLines.isEmpty {
                        currentHunks.append(DiffHunk(
                            oldStart: currentOldStart,
                            oldCount: currentOldCount,
                            newStart: currentNewStart,
                            newCount: currentNewCount,
                            lines: currentLines
                        ))
                    }
                    patches.append(FilePatch(filePath: file, hunks: currentHunks))
                }
                currentFile = line.replacingOccurrences(of: "+++ b/", with: "").replacingOccurrences(of: "+++ ", with: "")
                currentHunks = []
                currentLines = []
            } else if line.hasPrefix("@@") {
                if !currentLines.isEmpty {
                    currentHunks.append(DiffHunk(
                        oldStart: currentOldStart,
                        oldCount: currentOldCount,
                        newStart: currentNewStart,
                        newCount: currentNewCount,
                        lines: currentLines
                    ))
                    currentLines = []
                }
                // Parse @@ -1,5 +1,6 @@
                let components = line.components(separatedBy: " ")
                if components.count >= 3 {
                    let oldPart = components[1].replacingOccurrences(of: "-", with: "")
                    let newPart = components[2].replacingOccurrences(of: "+", with: "")

                    let oldNums = oldPart.components(separatedBy: ",")
                    let newNums = newPart.components(separatedBy: ",")

                    currentOldStart = Int(oldNums.first ?? "1") ?? 1
                    currentOldCount = oldNums.count > 1 ? (Int(oldNums[1]) ?? 1) : 1
                    currentNewStart = Int(newNums.first ?? "1") ?? 1
                    currentNewCount = newNums.count > 1 ? (Int(newNums[1]) ?? 1) : 1
                }
            } else if line.hasPrefix("+") {
                currentLines.append(DiffLine(kind: .addition, text: String(line.dropFirst())))
            } else if line.hasPrefix("-") {
                currentLines.append(DiffLine(kind: .deletion, text: String(line.dropFirst())))
            } else if line.hasPrefix(" ") || (!line.hasPrefix("diff ") && !line.hasPrefix("index ") && !line.hasPrefix("--- ")) {
                let text = line.hasPrefix(" ") ? String(line.dropFirst()) : line
                currentLines.append(DiffLine(kind: .context, text: text))
            }
        }

        if let file = currentFile {
            if !currentLines.isEmpty {
                currentHunks.append(DiffHunk(
                    oldStart: currentOldStart,
                    oldCount: currentOldCount,
                    newStart: currentNewStart,
                    newCount: currentNewCount,
                    lines: currentLines
                ))
            }
            patches.append(FilePatch(filePath: file, hunks: currentHunks))
        }

        return patches
    }

    /// Preflight verification: checks if a patch can apply cleanly without conflicts.
    public func preflight(originalContent: String, hunks: [DiffHunk]) -> PreflightResult {
        let originalLines = originalContent.components(separatedBy: .newlines)

        for hunk in hunks {
            var targetIdx = hunk.oldStart - 1
            for line in hunk.lines {
                switch line.kind {
                case .context, .deletion:
                    if targetIdx < 0 || targetIdx >= originalLines.count {
                        return .conflict(reason: "Hunk out of range", line: targetIdx + 1)
                    }
                    if originalLines[targetIdx] != line.text {
                        return .conflict(reason: "Content mismatch at line", line: targetIdx + 1)
                    }
                    targetIdx += 1
                case .addition:
                    break
                }
            }
        }
        return .ready
    }

    /// Applies a patch to a string with atomic validation.
    public func apply(originalContent: String, hunks: [DiffHunk]) throws -> String {
        let check = preflight(originalContent: originalContent, hunks: hunks)
        if case .conflict(let reason, let line) = check {
            throw NSError(domain: "DiffEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Preflight failed: \(reason) \(line)"])
        }

        let sourceLines = originalContent.components(separatedBy: .newlines)
        var outputLines: [String] = []
        var srcIdx = 0

        for hunk in hunks {
            let hunkStartIdx = hunk.oldStart - 1

            while srcIdx < hunkStartIdx && srcIdx < sourceLines.count {
                outputLines.append(sourceLines[srcIdx])
                srcIdx += 1
            }

            for line in hunk.lines {
                switch line.kind {
                case .context:
                    if srcIdx < sourceLines.count {
                        outputLines.append(sourceLines[srcIdx])
                        srcIdx += 1
                    }
                case .deletion:
                    if srcIdx < sourceLines.count {
                        srcIdx += 1
                    }
                case .addition:
                    outputLines.append(line.text)
                }
            }
        }

        while srcIdx < sourceLines.count {
            outputLines.append(sourceLines[srcIdx])
            srcIdx += 1
        }

        return outputLines.joined(separator: "\n")
    }
}
