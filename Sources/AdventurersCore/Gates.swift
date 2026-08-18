// AdventurersCore - Gates
// Deterministic certification: the model never decides completion

import Foundation

// MARK: - Syntax Gate

/// Validates brace/parenthesis balance, extracts code from markdown fences.
public struct SyntaxGate: Gate {
    public let name = "syntax"
    public let required = true

    public func evaluate(_ output: AgentOutput, context: GateContext) async -> GateResult {
        let code = extractCode(from: output.content)

        // Check brace balance
        let openBraces = code.filter { $0 == "{" }.count
        let closeBraces = code.filter { $0 == "}" }.count
        guard openBraces == closeBraces else {
            return GateResult(passed: false, gateName: name,
                              error: "Unbalanced braces: \(openBraces) open, \(closeBraces) close")
        }

        // Check parenthesis balance
        let openParens = code.filter { $0 == "(" }.count
        let closeParens = code.filter { $0 == ")" }.count
        guard openParens == closeParens else {
            return GateResult(passed: false, gateName: name,
                              error: "Unbalanced parentheses: \(openParens) open, \(closeParens) close")
        }

        return GateResult(passed: true, gateName: name, output: "Syntax OK")
    }

    private func extractCode(from content: String) -> String {
        // Extract from ``` fences if present
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

    private var seenHashes: [String] = []

    public init() {}

    public func evaluate(_ output: AgentOutput, context: GateContext) async -> GateResult {
        let hash = output.content.md5Hash

        // Check against all previous outputs in this task
        let previousHashes = context.previousOutputs.dropLast().map { $0.content.md5Hash }
        if previousHashes.contains(hash) {
            return GateResult(passed: false, gateName: name,
                              error: "Identical submission to a previous round")
        }

        seenHashes.append(hash)
        return GateResult(passed: true, gateName: name, output: "Unique submission")
    }
}

// MARK: - Compilation Gate

/// Compiles the output to check for syntax errors (for code tasks).
public struct CompilationGate: Gate {
    public let name = "compilation"
    public let required = false

    public func evaluate(_ output: AgentOutput, context: GateContext) async -> GateResult {
        // Stub: in production, compile with swiftc or appropriate compiler
        let code = extractCode(from: output.content)
        guard !code.isEmpty else {
            return GateResult(passed: false, gateName: name, error: "No code to compile")
        }
        return GateResult(passed: true, gateName: name, output: "Compilation check skipped (stub)")
    }

    private func extractCode(from content: String) -> String {
        content
    }
}

// MARK: - String Hashing

extension String {
    var md5Hash: String {
        guard let data = self.data(using: .utf8) else { return "" }
        var digest = [UInt8](repeating: 0, count: 16)
        data.withUnsafeBytes { body in
            _ = CC_MD5(body.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// CC_MD5 import
import CommonCrypto
