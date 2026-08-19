// AdventurersCore - Gates
// Deterministic certification: the model never decides completion

import Foundation
import CryptoKit

// MARK: - Syntax Gate

/// Validates brace/parenthesis balance, extracts code from markdown fences.
public struct SyntaxGate: Gate {
    public let name = "syntax"
    public let required = true

    public init() {}

    public func evaluate(_ output: AgentOutput, context: GateContext) async -> GateResult {
        let code = extractCode(from: output.content)

        let openBraces = code.filter { $0 == "{" }.count
        let closeBraces = code.filter { $0 == "}" }.count
        guard openBraces == closeBraces else {
            return GateResult(passed: false, gateName: name,
                              error: "Unbalanced braces: \(openBraces) open, \(closeBraces) close")
        }

        let openParens = code.filter { $0 == "(" }.count
        let closeParens = code.filter { $0 == ")" }.count
        guard openParens == closeParens else {
            return GateResult(passed: false, gateName: name,
                              error: "Unbalanced parentheses: \(openParens) open, \(closeParens) close")
        }

        let openBrackets = code.filter { $0 == "[" }.count
        let closeBrackets = code.filter { $0 == "]" }.count
        guard openBrackets == closeBrackets else {
            return GateResult(passed: false, gateName: name,
                              error: "Unbalanced square brackets: \(openBrackets) open, \(closeBrackets) close")
        }

        return GateResult(passed: true, gateName: name, output: "Syntax OK")
    }

    private func extractCode(from content: String) -> String {
        let pattern = #"```(?:\w+)?\n([\s\S]*?)```"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) else {
            return content
        }
        return String(content[Range(match.range(at: 1), in: content)!])
    }
}

// MARK: - Repeat Gate

/// Rejects verbatim identical submissions to prevent loops.
public struct RepeatGate: Gate {
    public let name = "repeat"
    public let required = true

    public init() {}

    public func evaluate(_ output: AgentOutput, context: GateContext) async -> GateResult {
        let hash = output.content.md5Hash
        let previousHashes = context.previousOutputs.dropLast().map { $0.content.md5Hash }
        if previousHashes.contains(hash) {
            return GateResult(passed: false, gateName: name,
                              error: "Identical submission to a previous round")
        }
        return GateResult(passed: true, gateName: name, output: "Unique submission")
    }
}

// MARK: - Compilation Gate

/// Compiles the output by running swift build to verify syntax and type correctness.
public struct CompilationGate: Gate {
    public let name = "compilation"
    public let required = false

    public init() {}

    public func evaluate(_ output: AgentOutput, context: GateContext) async -> GateResult {
        let code = output.content
        guard !code.isEmpty else {
            return GateResult(passed: false, gateName: name, error: "No code to compile")
        }

        // Extract Swift code from markdown fences if present
        let swiftCode = extractSwiftCode(from: code)
        guard !swiftCode.isEmpty else {
            return GateResult(passed: true, gateName: name, output: "No Swift code blocks found, skipping compilation")
        }

        // Write code to a temporary file and attempt compilation
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("adventurers_compile_check_\(UUID().uuidString).swift")

        do {
            try swiftCode.write(to: tempFile, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: tempFile) }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
            process.arguments = ["-typecheck", tempFile.path]

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            try process.run()
            process.waitUntilExit()

            let exitCode = process.terminationStatus
            if exitCode == 0 {
                return GateResult(passed: true, gateName: name, output: "Type check successful")
            } else {
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8) ?? "Type check failed"
                return GateResult(passed: false, gateName: name, error: errStr)
            }
        } catch {
            return GateResult(passed: false, gateName: name, error: "Compilation check failed: \(error.localizedDescription)")
        }
    }

    private func extractSwiftCode(from content: String) -> String {
        let pattern = #"```(?:swift)?\n([\s\S]*?)```"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) else {
            return ""
        }
        return String(content[Range(match.range(at: 1), in: content)!])
    }
}

// MARK: - Memory Gate

/// Bounds execution memory to avoid OOM crashes on large tasks.
public struct MemoryGate: Gate {
    public let name = "memory"
    public let required = false
    public let maxResidentBytes: UInt64

    public init(maxResidentBytes: UInt64 = 2 * 1024 * 1024 * 1024) { // Default: 2 GB
        self.maxResidentBytes = maxResidentBytes
    }

    public func evaluate(_ output: AgentOutput, context: GateContext) async -> GateResult {
        var usage = rusage()
        if getrusage(RUSAGE_SELF, &usage) == 0 {
            let residentBytes = UInt64(usage.ru_maxrss)
            let residentMB = residentBytes / (1024 * 1024)
            let maxMB = maxResidentBytes / (1024 * 1024)
            if residentBytes > maxResidentBytes {
                return GateResult(
                    passed: false,
                    gateName: name,
                    error: "Resident memory (\(residentMB)MB) exceeds safe threshold of \(maxMB)MB"
                )
            }
            return GateResult(passed: true, gateName: name, output: "Memory within safe bounds (\(residentMB)MB < \(maxMB)MB)")
        }

        return GateResult(passed: true, gateName: name, output: "Memory check skipped (unable to query task info)")
    }
}

// MARK: - Diff Gate

/// Validates that file changes are safe and won't corrupt existing code.
public struct DiffGate: Gate {
    public let name = "diff"
    public let required = false
    public let workspaceRoot: URL?

    public init(workspaceRoot: URL? = nil) {
        self.workspaceRoot = workspaceRoot
    }

    public func evaluate(_ output: AgentOutput, context: GateContext) async -> GateResult {
        let code = output.content

        // Check for destructive patterns
        let destructivePatterns = [
            "rm -rf",
            "rm -r /",
            "sudo rm",
            "sudo chmod",
            "chmod -R 777",
            "git push --force",
            "git push -f",
            "mkfs",
            "dd if=",
            ":(){ :|:& };:",  // fork bomb
        ]

        let lowercased = code.lowercased()
        for pattern in destructivePatterns {
            if lowercased.contains(pattern) {
                return GateResult(
                    passed: false,
                    gateName: name,
                    error: "Destructive command detected: '\(pattern)'"
                )
            }
        }

        // Check for sensitive file access
        let sensitivePaths = [
            "/etc/passwd",
            "/etc/shadow",
            "~/.ssh/id_rsa",
            "~/.ssh/id_ed25519",
            "~/.gnupg/",
            "/private/var/db/",
            ".env",
            ".env.production",
        ]

        for path in sensitivePaths {
            if lowercased.contains(path) {
                return GateResult(
                    passed: false,
                    gateName: name,
                    error: "Sensitive file access detected: '\(path)'"
                )
            }
        }

        // Validate diff format if present
        if code.contains("--- a/") || code.contains("+++ b/") {
            let diffEngine = DiffEngine.shared
            let patches = diffEngine.parseUnifiedDiff(code)

            if patches.isEmpty && (code.contains("@@") || code.contains("---")) {
                return GateResult(
                    passed: false,
                    gateName: name,
                    error: "Invalid diff format detected"
                )
            }

            // Check for suspiciously large diffs
            let totalLines = code.components(separatedBy: "\n").count
            if totalLines > 500 {
                return GateResult(
                    passed: false,
                    gateName: name,
                    error: "Diff too large (\(totalLines) lines). Break into smaller changes."
                )
            }
        }

        return GateResult(passed: true, gateName: name, output: "Diff validation passed")
    }
}

/// Certifies that output addresses key requirements in the initial task contract.
public struct ObjectiveGate: Gate {
    public let name = "objective"
    public let required = false

    public init() {}

    public func evaluate(_ output: AgentOutput, context: GateContext) async -> GateResult {
        let promptKeywords = context.contract.prompt.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 }

        guard !promptKeywords.isEmpty else {
            return GateResult(passed: true, gateName: name, output: "Objective verified")
        }

        let outputLower = output.content.lowercased()
        let matchCount = promptKeywords.filter { outputLower.contains($0) }.count
        let coverage = Double(matchCount) / Double(promptKeywords.count)

        if coverage < 0.20 && context.contract.prompt.count > 20 {
            return GateResult(
                passed: false,
                gateName: name,
                error: "Low objective relevance (\(Int(coverage * 100))% keyword coverage with task prompt)"
            )
        }

        return GateResult(passed: true, gateName: name, output: "Objective aligned (\(Int(coverage * 100))% coverage)")
    }
}

// MARK: - String Hashing

extension String {
    var md5Hash: String {
        guard let data = self.data(using: .utf8) else { return "" }
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
