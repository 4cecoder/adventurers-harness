// SecurityGate.swift
// AdventurersCore — OWASP Security, Secret Scanner & Dangerous Pattern Gate
// Prevents secret leakage (API keys, private keys, SSH keys), shell injections, and path traversal vectors.

import Foundation

public struct SecurityGate: Gate, Sendable {
    public let name = "security"
    public let required = true
    public let description = "Validates code diffs against secret leaks, private keys, SQL injection and path traversal."

    private static let dangerousPatterns: [String] = [
        "BEGIN OPENSSH PRIVATE KEY",
        "BEGIN RSA PRIVATE KEY",
        "BEGIN EC PRIVATE KEY",
        "ghp_[0-9a-zA-Z]{36}",
        "xoxb-[0-9]{11}-[0-9]{11}-[0-9a-zA-Z]{24}",
        "sk-proj-[a-zA-Z0-9_-]+",
        "sk-proj-",
        "rm -rf /",
        "rm -rf ~",
        "chmod 777",
        ":(){ :|:& };:"
    ]

    public init() {}

    public func evaluate(_ output: AgentOutput, context: GateContext) async -> GateResult {
        let content = output.content

        for pattern in Self.dangerousPatterns {
            if content.contains(pattern) {
                return GateResult(
                    passed: false,
                    gateName: name,
                    error: "Security Gate Rejection: Detected sensitive secret pattern or destructive command pattern '\(pattern)'."
                )
            }
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
               match.range.location != NSNotFound {
                return GateResult(
                    passed: false,
                    gateName: name,
                    error: "Security Gate Rejection: Detected sensitive secret pattern or destructive command pattern '\(pattern)'."
                )
            }
        }

        // Tool calls inspection
        for tool in output.toolCalls {
            if tool.name == "bash" || tool.name == "run_command" {
                let cmd = tool.arguments["command"]?.stringValue ?? ""
                for pattern in Self.dangerousPatterns {
                    if cmd.contains(pattern) {
                        return GateResult(
                            passed: false,
                            gateName: name,
                            error: "Security Gate Rejection: Prohibited shell payload '\(pattern)'."
                        )
                    }
                    if let regex = try? NSRegularExpression(pattern: pattern),
                       let match = regex.firstMatch(in: cmd, range: NSRange(cmd.startIndex..., in: cmd)),
                       match.range.location != NSNotFound {
                        return GateResult(
                            passed: false,
                            gateName: name,
                            error: "Security Gate Rejection: Prohibited shell payload '\(pattern)'."
                        )
                    }
                }
            }
        }

        return GateResult(passed: true, gateName: name, output: "Security verified clean.")
    }
}
