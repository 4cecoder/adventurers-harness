// AdventurersCore - ExecPolicy
// Rule-based execution policy engine for layered safety checks

import Foundation

/// Decision outcome for command execution policy check.
public enum ExecDecisionType: String, Sendable, Codable, Equatable {
    case allow
    case deny
    case askApproval
}

/// Pattern matching style for command policy rules.
public enum PatternMatchType: String, Sendable, Codable, Equatable {
    case exact
    case prefix
    case glob
    case regex
}

/// A rule in the execution policy engine.
public struct ExecPolicyRule: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var pattern: String
    public var matchType: PatternMatchType
    public var decision: ExecDecisionType
    public var workingDirectory: String?
    public var timeoutSeconds: Double?
    public var riskLevel: RiskLevel?

    public init(
        id: UUID = UUID(),
        name: String = "",
        pattern: String,
        matchType: PatternMatchType = .prefix,
        decision: ExecDecisionType,
        workingDirectory: String? = nil,
        timeoutSeconds: Double? = nil,
        riskLevel: RiskLevel? = nil
    ) {
        self.id = id
        self.name = name.isEmpty ? pattern : name
        self.pattern = pattern
        self.matchType = matchType
        self.decision = decision
        self.workingDirectory = workingDirectory
        self.timeoutSeconds = timeoutSeconds
        self.riskLevel = riskLevel
    }

    /// Evaluates if a given command and working directory matches this rule.
    public func matches(command: String, in workingDirectory: String? = nil) -> Bool {
        let trimmedCmd = command.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check working directory constraint if present
        if let requiredCwd = self.workingDirectory, !requiredCwd.isEmpty {
            guard let actualCwd = workingDirectory, !actualCwd.isEmpty else {
                return false
            }
            if !actualCwd.hasPrefix(requiredCwd) && actualCwd != requiredCwd {
                return false
            }
        }

        switch matchType {
        case .exact:
            return trimmedCmd == pattern.trimmingCharacters(in: .whitespacesAndNewlines)

        case .prefix:
            return trimmedCmd.hasPrefix(pattern)

        case .glob:
            return fnmatch(pattern: pattern, string: trimmedCmd)

        case .regex:
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return false
            }
            let nsString = trimmedCmd as NSString
            return regex.firstMatch(in: trimmedCmd, options: [], range: NSRange(location: 0, length: nsString.length)) != nil
        }
    }

    private func fnmatch(pattern: String, string: String) -> Bool {
        // Convert simple shell glob (*, ?) into NSRegularExpression
        var regexPattern = "^"
        for char in pattern {
            switch char {
            case "*": regexPattern.append(".*")
            case "?": regexPattern.append(".")
            case ".", "(", ")", "+", "|", "^", "$", "[", "]", "{", "}", "\\":
                regexPattern.append("\\\(char)")
            default:
                regexPattern.append(char)
            }
        }
        regexPattern.append("$")

        guard let regex = try? NSRegularExpression(pattern: regexPattern, options: [.caseInsensitive]) else {
            return false
        }
        let nsString = string as NSString
        return regex.firstMatch(in: string, options: [], range: NSRange(location: 0, length: nsString.length)) != nil
    }
}

extension RiskLevel: Codable {}

/// Result returned after evaluating a command against policy engine and dangerous detectors.
public struct ExecDecision: Sendable, Equatable {
    public let decision: ExecDecisionType
    public let matchingRule: ExecPolicyRule?
    public let dangerousMatch: DangerousMatch?
    public let reason: String

    public init(
        decision: ExecDecisionType,
        matchingRule: ExecPolicyRule? = nil,
        dangerousMatch: DangerousMatch? = nil,
        reason: String = ""
    ) {
        self.decision = decision
        self.matchingRule = matchingRule
        self.dangerousMatch = dangerousMatch
        self.reason = reason
    }
}

/// Evaluates commands against layered execution policy rules and dangerous command detectors.
public final class ExecPolicyEngine: Sendable {
    public static let shared = ExecPolicyEngine()

    private let defaultRules: [ExecPolicyRule]
    private let detector: DangerousCommandDetector

    public init(
        customDefaultRules: [ExecPolicyRule]? = nil,
        detector: DangerousCommandDetector = .shared
    ) {
        self.detector = detector
        self.defaultRules = customDefaultRules ?? Self.builtinDefaultRules()
    }

    /// Built-in baseline rules for developer safety.
    public static func builtinDefaultRules() -> [ExecPolicyRule] {
        [
            // Always allow safe read-only developer commands
            ExecPolicyRule(name: "Swift safe read commands", pattern: "swift package describe", matchType: .prefix, decision: .allow),
            ExecPolicyRule(name: "Git status & diff", pattern: "git (status|diff|log|branch|show)", matchType: .regex, decision: .allow),
            ExecPolicyRule(name: "Listing files", pattern: "ls *", matchType: .glob, decision: .allow),
            ExecPolicyRule(name: "Grep / Ripgrep", pattern: "(grep|rg) .*", matchType: .regex, decision: .allow),
            ExecPolicyRule(name: "Find files", pattern: "find .*", matchType: .regex, decision: .allow),
            ExecPolicyRule(name: "Swift build/test", pattern: "swift (build|test)", matchType: .regex, decision: .allow),

            // Deny destructive file wipe commands
            ExecPolicyRule(name: "Deny root wipe", pattern: "rm -rf /", matchType: .prefix, decision: .deny),
            ExecPolicyRule(name: "Deny fork bomb", pattern: ":(){ :|:& };:", matchType: .prefix, decision: .deny),
            ExecPolicyRule(name: "Deny shadow file dump", pattern: "cat /etc/shadow", matchType: .exact, decision: .deny),
        ]
    }

    /// Evaluates a command across layers:
    /// 1. Dangerous Command Detector (if dangerous -> deny or ask approval based on severity)
    /// 2. Custom rules (highest precedence)
    /// 3. Workspace rules
    /// 4. Default rules
    /// 5. Fallback decision (default: askApproval for destructive/execute, allow for readOnly)
    public func evaluate(
        command: String,
        workingDirectory: String? = nil,
        workspaceRules: [ExecPolicyRule] = [],
        customRules: [ExecPolicyRule] = [],
        fallbackDecision: ExecDecisionType = .askApproval
    ) -> ExecDecision {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Dangerous Command Detector check
        if let danger = detector.detectDangerousCommand(trimmed) {
            return ExecDecision(
                decision: .deny,
                matchingRule: nil,
                dangerousMatch: danger,
                reason: "Blocked by DangerousCommandDetector: \(danger.reason)"
            )
        }

        // 2. Custom rules layer
        for rule in customRules {
            if rule.matches(command: trimmed, in: workingDirectory) {
                return ExecDecision(
                    decision: rule.decision,
                    matchingRule: rule,
                    dangerousMatch: nil,
                    reason: "Matched custom policy rule '\(rule.name)'"
                )
            }
        }

        // 3. Workspace rules layer
        for rule in workspaceRules {
            if rule.matches(command: trimmed, in: workingDirectory) {
                return ExecDecision(
                    decision: rule.decision,
                    matchingRule: rule,
                    dangerousMatch: nil,
                    reason: "Matched workspace policy rule '\(rule.name)'"
                )
            }
        }

        // 4. Default rules layer
        for rule in defaultRules {
            if rule.matches(command: trimmed, in: workingDirectory) {
                return ExecDecision(
                    decision: rule.decision,
                    matchingRule: rule,
                    dangerousMatch: nil,
                    reason: "Matched default policy rule '\(rule.name)'"
                )
            }
        }

        // 5. Fallback
        return ExecDecision(
            decision: fallbackDecision,
            matchingRule: nil,
            dangerousMatch: nil,
            reason: "No explicit rule match; using fallback policy '\(fallbackDecision.rawValue)'"
        )
    }
}
