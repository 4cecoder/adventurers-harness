// AdventurersCore - Cactus Needle 2 On-Device Agentic Intelligence & Pre-Processing Layer
// Ultra-fast (<15ms, 14MB footprint) local tool routing, schema-constrained extraction, and output compaction.

import Foundation

// MARK: - Needle Routing & Decision Models

public enum NeedleRouteMode: Sendable, Equatable {
    /// High-confidence intent mapped directly to an immediate local tool call without cloud latency.
    case localFastExecute(tool: String, arguments: [String: String])
    /// Structured response or direct extraction ready for instant presentation.
    case directStructuredResponse(json: String)
    /// Escalate to cloud frontier model (Gemini / Claude / OpenAI) for complex reasoning.
    case cloudEscalate(reason: String)
}

public struct NeedleDecision: Sendable {
    public let mode: NeedleRouteMode
    public let confidence: Double
    public let latencyMs: Double
    public let rationale: String
    public let tokenSavingsEstimated: Int

    public init(
        mode: NeedleRouteMode,
        confidence: Double,
        latencyMs: Double,
        rationale: String,
        tokenSavingsEstimated: Int
    ) {
        self.mode = mode
        self.confidence = confidence
        self.latencyMs = latencyMs
        self.rationale = rationale
        self.tokenSavingsEstimated = tokenSavingsEstimated
    }
}

// MARK: - Needle Processor Engine

public final class NeedleProcessor: Sendable {
    public static let shared = NeedleProcessor()

    public let confidenceThreshold: Double

    public init(confidenceThreshold: Double = 0.80) {
        self.confidenceThreshold = confidenceThreshold
    }

    /// Evaluates user query against local tool dictionary and workspace context.
    public func process(
        prompt: String,
        workspaceFiles: [String] = [],
        knownTools: [String] = ["run_command", "view_file", "grep_search", "list_dir"]
    ) -> NeedleDecision {
        let startTime = CFAbsoluteTimeGetCurrent()
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // 1. Direct Quick Tool Patterns
        // Test suite runner
        if matchesAny(lower, patterns: ["run test", "run tests", "swift test", "test project", "run the tests", "execute tests", "run the test suite", "run unit tests"]) {
            let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            return NeedleDecision(
                mode: .localFastExecute(tool: "run_command", arguments: ["command": "swift test --filter AdventurersCoreTests"]),
                confidence: 0.98,
                latencyMs: latency,
                rationale: "Matched explicit test execution pattern with high confidence.",
                tokenSavingsEstimated: 450
            )
        }

        // Build / compile commands
        if matchesAny(lower, patterns: ["swift build", "build project", "compile project", "build the app", "run build", "build harness"]) {
            let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            return NeedleDecision(
                mode: .localFastExecute(tool: "run_command", arguments: ["command": "swift build"]),
                confidence: 0.97,
                latencyMs: latency,
                rationale: "Matched build/compile execution pattern.",
                tokenSavingsEstimated: 400
            )
        }

        // Git status check
        if matchesAny(lower, patterns: ["git status", "check status", "what changed", "modified files", "git changes", "check git status", "show git status"]) {
            let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            return NeedleDecision(
                mode: .localFastExecute(tool: "run_command", arguments: ["command": "git status -s"]),
                confidence: 0.96,
                latencyMs: latency,
                rationale: "Matched git working copy status inquiry.",
                tokenSavingsEstimated: 320
            )
        }

        // Git diff check
        if matchesAny(lower, patterns: ["git diff", "show diff", "show changes", "view diff", "what are the diffs", "show git diff"]) {
            let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            return NeedleDecision(
                mode: .localFastExecute(tool: "run_command", arguments: ["command": "git diff"]),
                confidence: 0.95,
                latencyMs: latency,
                rationale: "Matched working tree diff examination.",
                tokenSavingsEstimated: 600
            )
        }

        // Git log / recent commits
        if matchesAny(lower, patterns: ["git log", "recent commits", "show git log", "show commits", "git history", "commit history"]) {
            let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            return NeedleDecision(
                mode: .localFastExecute(tool: "run_command", arguments: ["command": "git log -n 5 --oneline"]),
                confidence: 0.95,
                latencyMs: latency,
                rationale: "Matched git commit history inspection.",
                tokenSavingsEstimated: 450
            )
        }

        // Git branch listing
        if matchesAny(lower, patterns: ["git branch", "show branches", "list branches", "current branch"]) {
            let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            return NeedleDecision(
                mode: .localFastExecute(tool: "run_command", arguments: ["command": "git branch"]),
                confidence: 0.95,
                latencyMs: latency,
                rationale: "Matched git branch enumeration.",
                tokenSavingsEstimated: 250
            )
        }

        // File list / Directory exploration
        if matchesAny(lower, patterns: ["list files", "ls", "show files", "what files are here", "explore directory", "list dir", "list directory"]) {
            let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            return NeedleDecision(
                mode: .localFastExecute(tool: "list_dir", arguments: ["path": "."]),
                confidence: 0.92,
                latencyMs: latency,
                rationale: "Matched directory contents enumeration.",
                tokenSavingsEstimated: 250
            )
        }

        // File Creation ("create a new file called X", "touch X", "create file X", "new file X")
        if lower.contains("create a new file") || lower.contains("create file") || lower.contains("new file") || lower.hasPrefix("touch ") {
            var targetPath = ""
            let words = trimmed.split(separator: " ").map(String.init)
            if let idx = words.firstIndex(where: { ["called", "named"].contains($0.lowercased()) }), idx + 1 < words.count {
                let candidate = words[idx + 1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'` "))
                if !candidate.isEmpty {
                    targetPath = candidate
                }
            } else if let idx = words.firstIndex(where: { ["touch", "file"].contains($0.lowercased()) }), idx + 1 < words.count {
                let candidate = words[idx + 1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'` "))
                if candidate.contains(".") || candidate.contains("/") {
                    targetPath = candidate
                }
            } else if let lastWord = words.last {
                let candidate = lastWord.trimmingCharacters(in: CharacterSet(charactersIn: "\"'` "))
                if candidate.contains(".") || candidate.contains("/") {
                    targetPath = candidate
                }
            }
            if !targetPath.isEmpty && !targetPath.contains("how") && targetPath != "file" && targetPath != "called" && targetPath != "named" {
                let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                return NeedleDecision(
                    mode: .localFastExecute(tool: "write_to_file", arguments: ["path": targetPath, "content": ""]),
                    confidence: 0.93,
                    latencyMs: latency,
                    rationale: "Matched file creation pattern for \(targetPath).",
                    tokenSavingsEstimated: 350
                )
            }
        }

        // Exact code search / Grep
        if lower.hasPrefix("find ") || lower.hasPrefix("search for ") || lower.hasPrefix("grep ") {
            var query = trimmed
            if lower.hasPrefix("search for ") {
                query = String(trimmed.dropFirst(11))
            } else if lower.hasPrefix("find ") {
                query = String(trimmed.dropFirst(5))
            } else if lower.hasPrefix("grep ") {
                query = String(trimmed.dropFirst(5))
            }
            // Strip trailing noise like "in the codebase", "in files", "in project"
            for suffix in [" in the codebase", " in codebase", " in the project", " in files", " in repo", " in repository"] {
                if query.lowercased().hasSuffix(suffix) {
                    query = String(query.dropLast(suffix.count))
                }
            }
            query = query.trimmingCharacters(in: CharacterSet(charactersIn: "\"'` "))

            if !query.isEmpty && !query.contains("how") && !query.contains("why") {
                let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                return NeedleDecision(
                    mode: .localFastExecute(tool: "grep_search", arguments: ["query": query]),
                    confidence: 0.90,
                    latencyMs: latency,
                    rationale: "Extracted exact pattern query for instant codebase grep.",
                    tokenSavingsEstimated: 400
                )
            }
        }

        // View specific target file (workspace match or explicit path/filename)
        if lower.hasPrefix("view ") || lower.hasPrefix("read ") || lower.hasPrefix("open ") || lower.hasPrefix("show file ") || lower.hasPrefix("show me ") || lower.hasPrefix("cat ") {
            // First check workspaceFiles
            for file in workspaceFiles {
                let filename = (file as NSString).lastPathComponent.lowercased()
                if lower.contains(filename) {
                    let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                    return NeedleDecision(
                        mode: .localFastExecute(tool: "view_file", arguments: ["path": file]),
                        confidence: 0.95,
                        latencyMs: latency,
                        rationale: "Matched explicit file reading request for \(file).",
                        tokenSavingsEstimated: 350
                    )
                }
            }

            // If not found in workspaceFiles, extract standalone path/filename pattern (e.g., "show me Package.swift", "read README.md", "cat Sources/Main.swift")
            let words = trimmed.split(separator: " ").map(String.init)
            if let lastWord = words.last {
                let candidate = lastWord.trimmingCharacters(in: CharacterSet(charactersIn: "\"'` "))
                if (candidate.contains(".") || candidate.contains("/")) && !candidate.contains("?") && candidate.count > 2 {
                    let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                    return NeedleDecision(
                        mode: .localFastExecute(tool: "view_file", arguments: ["path": candidate]),
                        confidence: 0.92,
                        latencyMs: latency,
                        rationale: "Extracted target file path for direct viewing: \(candidate).",
                        tokenSavingsEstimated: 350
                    )
                }
            }
        }

        // Structured Contact Extraction ("extract contact: ...")
        if lower.contains("extract contact") || (lower.contains("name") && lower.contains("email") && lower.contains("@")) {
            if let emailMatch = trimmed.range(of: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}", options: .regularExpression) {
                let email = String(trimmed[emailMatch])
                // Extract name candidate before or near email
                var name: String? = nil
                if let nameMatch = trimmed.range(of: "([A-Z][a-z]+(?: [A-Z][a-z]+)+)", options: .regularExpression) {
                    name = String(trimmed[nameMatch])
                }
                let json = "{\"name\": \(name != nil ? "\"\(name!)\"" : "null"), \"email\": \"\(email)\"}"
                let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                return NeedleDecision(
                    mode: .directStructuredResponse(json: json),
                    confidence: 0.91,
                    latencyMs: latency,
                    rationale: "Locally extracted structured contact record without cloud tokens.",
                    tokenSavingsEstimated: 280
                )
            }
        }

        // Categorize Task (BUG / FEATURE / DOCS)
        if lower.contains("categorize") || (lower.contains("category:") && (lower.contains("bug") || lower.contains("feature") || lower.contains("doc"))) {
            var category = "FEATURE"
            if lower.contains("crash") || lower.contains("hang") || lower.contains("error") || lower.contains("fail") || lower.contains("bug") || lower.contains("broken") {
                category = "BUG"
            } else if lower.contains("readme") || lower.contains("doc") || lower.contains("contributing") || lower.contains("guide") || lower.contains("typo") {
                category = "DOCS"
            }
            let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            return NeedleDecision(
                mode: .directStructuredResponse(json: "{\"category\": \"\(category)\"}"),
                confidence: 0.90,
                latencyMs: latency,
                rationale: "Locally classified item category as \(category).",
                tokenSavingsEstimated: 200
            )
        }

        // Default: Escalate to Cloud Model with rationale
        let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        return NeedleDecision(
            mode: .cloudEscalate(reason: "Multi-step reasoning, synthesis, or creative code refactoring required."),
            confidence: 0.40,
            latencyMs: latency,
            rationale: "Prompt involves open-ended reasoning; routed to Cloud Frontier Model.",
            tokenSavingsEstimated: 0
        )
    }

    private func matchesAny(_ text: String, patterns: [String]) -> Bool {
        for pattern in patterns {
            if text == pattern || text.hasPrefix(pattern + " ") || text.hasSuffix(" " + pattern) {
                return true
            }
        }
        return false
    }
}

// MARK: - Needle Output Compactor & Filter

public struct NeedleOutputCompactor: Sendable {

    /// Compresses verbose compiler and build logs down to actionable error/warning lines.
    public static func compactBuildLog(_ raw: String, maxLines: Int = 30) -> String {
        let lines = raw.components(separatedBy: "\n")
        guard lines.count > maxLines else { return raw }

        var essentialLines: [String] = []
        var errorCount = 0
        var warningCount = 0

        for line in lines {
            let lower = line.lowercased()
            if lower.contains("error:") || lower.contains("fatal error") || lower.contains("failed") {
                essentialLines.append(line)
                errorCount += 1
            } else if lower.contains("warning:") {
                if warningCount < 5 {
                    essentialLines.append(line)
                }
                warningCount += 1
            }
        }

        if essentialLines.isEmpty {
            // Keep head and tail if no specific errors found
            let head = lines.prefix(10)
            let tail = lines.suffix(10)
            return (head + ["... [\(lines.count - 20) lines suppressed by Needle 2 Compactor] ..."] + tail).joined(separator: "\n")
        }

        let summary = "⚡ [Needle 2 Compactor: Extracted \(errorCount) errors, \(warningCount) warnings from \(lines.count) lines]"
        return ([summary] + essentialLines).joined(separator: "\n")
    }

    /// Compresses massive git diff outputs into structured hunk summaries.
    public static func compactDiff(_ raw: String, maxHunks: Int = 15) -> String {
        let lines = raw.components(separatedBy: "\n")
        guard lines.count > 100 else { return raw }

        var compacted: [String] = []
        var modifiedLines = 0

        for line in lines {
            if line.hasPrefix("diff --git") {
                compacted.append("\n📁 " + line)
            } else if line.hasPrefix("@@") {
                compacted.append(line)
            } else if line.hasPrefix("+") || line.hasPrefix("-") {
                if !line.hasPrefix("+++") && !line.hasPrefix("---") {
                    compacted.append(line)
                    modifiedLines += 1
                }
            }
        }

        let header = "⚡ [Needle 2 Diff Compactor: \(modifiedLines) modifications summarized]"
        return header + "\n" + compacted.prefix(maxHunks * 5).joined(separator: "\n")
    }
}
