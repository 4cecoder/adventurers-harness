// AdventurersCore - DangerousCommandDetector
// Detects high-risk shell commands, destructive patterns, and shell escapes

import Foundation

/// Structured match result from dangerous command detection.
public struct DangerousMatch: Sendable, Equatable {
    public let command: String
    public let pattern: String
    public let risk: RiskLevel
    public let reason: String
    public let suggestedAlternative: String?

    public init(
        command: String,
        pattern: String,
        risk: RiskLevel = .destructive,
        reason: String,
        suggestedAlternative: String? = nil
    ) {
        self.command = command
        self.pattern = pattern
        self.risk = risk
        self.reason = reason
        self.suggestedAlternative = suggestedAlternative
    }
}

/// Detects dangerous commands, destructive operations, sensitive access, and wrapped shell escapes.
public final class DangerousCommandDetector: Sendable {
    public static let shared = DangerousCommandDetector()

    public init() {}

    public struct PatternRule: Sendable {
        public let pattern: String
        public let risk: RiskLevel
        public let reason: String
        public let suggestedAlternative: String?
        public let isRegex: Bool

        public init(
            pattern: String,
            risk: RiskLevel = .destructive,
            reason: String,
            suggestedAlternative: String? = nil,
            isRegex: Bool = false
        ) {
            self.pattern = pattern
            self.risk = risk
            self.reason = reason
            self.suggestedAlternative = suggestedAlternative
            self.isRegex = isRegex
        }
    }

    /// Unwraps layered shell execution wrappers (e.g. bash -c, zsh -c, sh -c, sudo, osascript, eval, env).
    public func unwrapCommand(_ command: String) -> [String] {
        var results: [String] = [command]
        var queue: [String] = [command]
        var seen: Set<String> = [command]

        while !queue.isEmpty {
            let current = queue.removeFirst().trimmingCharacters(in: .whitespacesAndNewlines)

            // Strip leading sudo
            if current.hasPrefix("sudo ") {
                let sub = String(current.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if !seen.contains(sub) && !sub.isEmpty {
                    seen.insert(sub)
                    results.append(sub)
                    queue.append(sub)
                }
            }

            // Strip eval
            if current.hasPrefix("eval ") {
                let sub = String(current.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                let cleaned = stripQuotes(sub)
                if !seen.contains(cleaned) && !cleaned.isEmpty {
                    seen.insert(cleaned)
                    results.append(cleaned)
                    queue.append(cleaned)
                }
            }

            // Strip osascript -e
            if current.contains("osascript") {
                if let extracted = extractArgument(from: current, flag: "-e") {
                    let cleaned = stripQuotes(extracted)
                    if !seen.contains(cleaned) && !cleaned.isEmpty {
                        seen.insert(cleaned)
                        results.append(cleaned)
                        queue.append(cleaned)
                    }
                }
            }

            // Check for shell invocation: bash -c "...", zsh -c "...", sh -c "..."
            let shellRegexPattern = #"(?:^|[;&|\s])(?:/bin/|/usr/bin/|/usr/local/bin/)?(bash|zsh|sh|dash|ksh)\s+(?:-[a-zA-Z]*c[a-zA-Z]*)\s+((?:'[^']*')|(?:"[^"]*")|(?:[^\s;&|]+))"#
            if let regex = try? NSRegularExpression(pattern: shellRegexPattern, options: [.caseInsensitive]) {
                let nsString = current as NSString
                let matches = regex.matches(in: current, options: [], range: NSRange(location: 0, length: nsString.length))
                for match in matches {
                    if match.numberOfRanges >= 3 {
                        let argRange = match.range(at: 2)
                        let rawArg = nsString.substring(with: argRange)
                        let unwrapped = stripQuotes(rawArg)
                        if !seen.contains(unwrapped) && !unwrapped.isEmpty {
                            seen.insert(unwrapped)
                            results.append(unwrapped)
                            queue.append(unwrapped)
                        }
                    }
                }
            }

            // Split chained commands by semicolons, &&, ||, and pipes |
            let subCommands = splitPipeline(current)
            for sub in subCommands where sub != current {
                let trimmed = sub.trimmingCharacters(in: .whitespacesAndNewlines)
                if !seen.contains(trimmed) && !trimmed.isEmpty {
                    seen.insert(trimmed)
                    results.append(trimmed)
                    queue.append(trimmed)
                }
            }
        }

        return results
    }

    private func stripQuotes(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") && trimmed.count >= 2) ||
           (trimmed.hasPrefix("'") && trimmed.hasSuffix("'") && trimmed.count >= 2) {
            let start = trimmed.index(after: trimmed.startIndex)
            let end = trimmed.index(before: trimmed.endIndex)
            return String(trimmed[start..<end])
        }
        return trimmed
    }

    private func extractArgument(from input: String, flag: String) -> String? {
        let pattern = "\(NSRegularExpression.escapedPattern(for: flag))\\s+((?:'[^']*')|(?:\"[^\"]*\")|(?:\\S+))"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = input as NSString
        guard let match = regex.firstMatch(in: input, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2 else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    private func splitPipeline(_ command: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var inSingleQuote = false
        var inDoubleQuote = false
        var escaped = false

        for char in command {
            if escaped {
                current.append(char)
                escaped = false
                continue
            }
            if char == "\\" {
                escaped = true
                current.append(char)
                continue
            }
            if char == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
                current.append(char)
                continue
            }
            if char == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
                current.append(char)
                continue
            }

            if !inSingleQuote && !inDoubleQuote {
                if char == ";" || char == "|" || char == "&" {
                    let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        parts.append(trimmed)
                    }
                    current = ""
                    continue
                }
            }
            current.append(char)
        }

        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            parts.append(trimmed)
        }
        return parts
    }

    /// Evaluates a command against standard dangerous patterns.
    public func detectDangerousCommand(_ command: String) -> DangerousMatch? {
        let commandsToTest = unwrapCommand(command)

        let rules: [PatternRule] = [
            // 1. Filesystem destruction
            PatternRule(
                pattern: #"\brm\s+(?:-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*|-[a-zA-Z]*f[a-zA-Z]*r[a-zA-Z]*)\s+(?:/\s*$|/\*|~|/\bbin\b|/\busr\b|/\betc\b|/\bvar\b|/\bSystem\b|/\bLibrary\b|\.\s*$)"#,
                risk: .destructive,
                reason: "Recursive force deletion of root, home, system paths, or current directory",
                suggestedAlternative: "Use targeted rm on specific files or move to trash",
                isRegex: true
            ),
            PatternRule(
                pattern: #"\bmkfs(?:\.[a-zA-Z0-9]+)?\b"#,
                risk: .destructive,
                reason: "Formatting filesystem volume which erases all data",
                suggestedAlternative: "Verify target device or use non-destructive disk utilities",
                isRegex: true
            ),
            PatternRule(
                pattern: #"\bdd\s+.*?(?:of=/dev/(?:r?disk[0-9]+|sd[a-z]|nvme[0-9]+n[0-9]+|zero|null))"#,
                risk: .destructive,
                reason: "Raw block device write via dd",
                suggestedAlternative: "Use safe file copy tools or inspect disk identifier carefully",
                isRegex: true
            ),
            PatternRule(
                pattern: #"\b(?:chmod|chown)\s+(?:-[a-zA-Z]*R[a-zA-Z]*)\s+(?:777|000|root)\s+(?:/|/\*|~|\.\s*$)"#,
                risk: .destructive,
                reason: "Recursive permission wipe on sensitive directory root or home",
                suggestedAlternative: "Apply permissions strictly to specific workspace folders",
                isRegex: true
            ),

            // 2. Untrusted remote execution piped to shell
            PatternRule(
                pattern: #"(?:curl|wget|fetch)\s+[^|;]+\|\s*(?:sudo\s+)?(?:bash|sh|zsh|python|perl|ruby)"#,
                risk: .destructive,
                reason: "Piping remote network scripts directly into an executable shell interpreter",
                suggestedAlternative: "Download script first, inspect contents, and execute locally",
                isRegex: true
            ),

            // 3. Process termination & system bombs
            PatternRule(
                pattern: #"\bkillall\s+-9\s+(?:launchd|kernel_task|loginwindow|Finder|Dock|WindowServer|SystemUIServer|init)\b"#,
                risk: .destructive,
                reason: "Force killing critical macOS system services or window server",
                suggestedAlternative: "Target specific worker processes by name or PID",
                isRegex: true
            ),
            PatternRule(
                pattern: #":\(\)\s*\{\s*:\s*\|\s*:\s*&\s*\}\s*;\s*:"#,
                risk: .destructive,
                reason: "Fork bomb process exhaustion attack",
                suggestedAlternative: nil,
                isRegex: true
            ),

            // 4. Destructive Git commands
            PatternRule(
                pattern: #"\bgit\s+push\s+(?:.*?\s+)?(?:--force|-f)\s+(?:[^\s]+\s+)?(?:main|master|prod|production|release)(?:\s+|$)"#,
                risk: .destructive,
                reason: "Force pushing destructive history rewrite to main/master/production branch",
                suggestedAlternative: "Use standard git push or push to a feature branch with --force-with-lease",
                isRegex: true
            ),
            PatternRule(
                pattern: #"\bgit\s+reset\s+--hard\s+(?:HEAD~[0-9]{2,}|[0-9a-f]{40}|origin/main|origin/master)"#,
                risk: .destructive,
                reason: "Hard reset discarding extensive uncommitted and committed local work",
                suggestedAlternative: "Use git stash or git reset --soft to preserve file changes",
                isRegex: true
            ),
            PatternRule(
                pattern: #"\bgit\s+clean\s+-(?:[a-zA-Z]*f[a-zA-Z]*d[a-zA-Z]*x[a-zA-Z]*)\b"#,
                risk: .destructive,
                reason: "Aggressive git clean removing untracked and ignored build artifacts permanently",
                suggestedAlternative: "Run 'git clean -n' dry-run first to preview deletions",
                isRegex: true
            ),

            // 5. System partition and secure device tampering
            PatternRule(
                pattern: #"\b(?:diskutil\s+(?:eraseDisk|partitionDisk|unmountDisk\s+force)|csrutil\s+disable|nvram\s+-c)\b"#,
                risk: .destructive,
                reason: "Disk wiping or macOS system integrity policy manipulation",
                suggestedAlternative: "Use standard disk management UI",
                isRegex: true
            ),

            // 6. Sensitive credential tampering
            PatternRule(
                pattern: #"\b(?:cat|cp|mv|rm|sed)\s+.*?(?:/etc/shadow|/etc/sudoers|~/.ssh/id_rsa|~/.ssh/id_ed25519|~/.gnupg/secring)"#,
                risk: .destructive,
                reason: "Direct modification or exfiltration of system secrets and private keys",
                suggestedAlternative: "Use standard ssh-add or gpg key management utilities",
                isRegex: true
            )
        ]

        for candidate in commandsToTest {
            for rule in rules {
                if rule.isRegex {
                    if let regex = try? NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive]) {
                        let nsCandidate = candidate as NSString
                        if regex.firstMatch(in: candidate, options: [], range: NSRange(location: 0, length: nsCandidate.length)) != nil {
                            return DangerousMatch(
                                command: candidate,
                                pattern: rule.pattern,
                                risk: rule.risk,
                                reason: rule.reason,
                                suggestedAlternative: rule.suggestedAlternative
                            )
                        }
                    }
                } else {
                    if candidate.lowercased().contains(rule.pattern.lowercased()) {
                        return DangerousMatch(
                            command: candidate,
                            pattern: rule.pattern,
                            risk: rule.risk,
                            reason: rule.reason,
                            suggestedAlternative: rule.suggestedAlternative
                        )
                    }
                }
            }
        }

        return nil
    }
}
