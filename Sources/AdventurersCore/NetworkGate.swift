// AdventurersCore - Network Permission Gate
// Task 2.3: Network Permission Gate (Gate #7 in the harness pipeline)

import Foundation
import LLMProviders

// MARK: - Network Protocol

/// Supported network protocols for filtering and gating.
public enum NetworkProtocol: String, Sendable, Codable, Equatable, Hashable, CaseIterable {
    case http = "http"
    case https = "https"
    case ws = "ws"
    case wss = "wss"
    case tcp = "tcp"
    case udp = "udp"
    case ssh = "ssh"
    case ftp = "ftp"
    case dns = "dns"
}

// MARK: - Network Target

/// Extracted network target inspected from tool calls or commands.
public struct NetworkTarget: Sendable, Equatable {
    public let `protocol`: NetworkProtocol
    public let host: String
    public let port: Int?
    public let rawTarget: String
    public let source: String

    public init(
        protocol: NetworkProtocol,
        host: String,
        port: Int? = nil,
        rawTarget: String,
        source: String
    ) {
        self.protocol = `protocol`
        self.host = host.lowercased()
        self.port = port
        self.rawTarget = rawTarget
        self.source = source
    }
}

// MARK: - Network Gate Configuration

/// Configuration policies for the NetworkGate.
public struct NetworkGateConfig: Sendable {
    public var allowedProtocols: Set<NetworkProtocol>
    public var allowedHosts: [String]
    public var deniedHosts: [String]
    public var allowedPorts: Set<Int>?
    public var inspectContent: Bool

    /// Default recommended host allowlist for developer workflows and AI providers.
    public static let defaultAllowedHosts: [String] = [
        "*.github.com",
        "*.githubusercontent.com",
        "api.anthropic.com",
        "generativelanguage.googleapis.com",
        "api.openai.com",
        "localhost",
        "127.0.0.1",
    ]

    public static let defaultDeniedHosts: [String] = [
        "*.onion",
        "169.254.169.254", // AWS/cloud metadata service
        "metadata.google.internal", // GCP metadata service
    ]

    public init(
        allowedProtocols: Set<NetworkProtocol> = [.https, .http, .ws, .wss],
        allowedHosts: [String] = NetworkGateConfig.defaultAllowedHosts,
        deniedHosts: [String] = NetworkGateConfig.defaultDeniedHosts,
        allowedPorts: Set<Int>? = nil,
        inspectContent: Bool = true
    ) {
        self.allowedProtocols = allowedProtocols
        self.allowedHosts = allowedHosts
        self.deniedHosts = deniedHosts
        self.allowedPorts = allowedPorts
        self.inspectContent = inspectContent
    }
}

// MARK: - Network Gate

/// Gate #7 in the harness pipeline.
/// Inspects tool calls and proposed commands for outbound network targets,
/// filtering by network protocol and validating hosts against wildcard allow/denylists.
public struct NetworkGate: Gate {
    public let name = "network"
    public let required: Bool
    public let config: NetworkGateConfig

    public init(required: Bool = false, config: NetworkGateConfig = NetworkGateConfig()) {
        self.required = required
        self.config = config
    }

    public func evaluate(_ output: AgentOutput, context: GateContext) async -> GateResult {
        let targets = extractNetworkTargets(from: output)

        if targets.isEmpty {
            return GateResult(
                passed: true,
                gateName: name,
                output: "No outbound network targets detected"
            )
        }

        var validatedCount = 0
        for target in targets {
            // 1. Protocol filtering
            guard config.allowedProtocols.contains(target.protocol) else {
                return GateResult(
                    passed: false,
                    gateName: name,
                    error: "Disallowed network protocol '\(target.protocol.rawValue)' for target '\(target.rawTarget)' (source: \(target.source))"
                )
            }

            // 2. Port filtering if specified
            if let allowedPorts = config.allowedPorts, let port = target.port {
                guard allowedPorts.contains(port) else {
                    return GateResult(
                        passed: false,
                        gateName: name,
                        error: "Disallowed destination port '\(port)' for host '\(target.host)'"
                    )
                }
            }

            // 3. Denylist check (takes strict precedence)
            for deniedPattern in config.deniedHosts {
                if Self.matchesWildcard(pattern: deniedPattern, host: target.host) {
                    return GateResult(
                        passed: false,
                        gateName: name,
                        error: "Network access denied: Host '\(target.host)' matches denylist pattern '\(deniedPattern)'"
                    )
                }
            }

            // 4. Allowlist check (if allowlist is populated)
            if !config.allowedHosts.isEmpty {
                let isAllowed = config.allowedHosts.contains { pattern in
                    Self.matchesWildcard(pattern: pattern, host: target.host)
                }
                guard isAllowed else {
                    return GateResult(
                        passed: false,
                        gateName: name,
                        error: "Network access blocked: Host '\(target.host)' is not in allowlist"
                    )
                }
            }

            validatedCount += 1
        }

        let summary = targets.map { "\($0.protocol.rawValue)://\($0.host)" }.joined(separator: ", ")
        return GateResult(
            passed: true,
            gateName: name,
            output: "Network access certified (\(validatedCount) target\(validatedCount == 1 ? "" : "s") authorized: \(summary))"
        )
    }

    // MARK: - Wildcard Matching

    /// Matches hostnames supporting `*.domain.com`, `*` wildcard prefixes, and exact matches.
    public static func matchesWildcard(pattern: String, host: String) -> Bool {
        let pat = pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if pat == "*" || pat == "*.*" {
            return true
        }

        if pat == h {
            return true
        }

        if pat.hasPrefix("*.") {
            let rootDomain = String(pat.dropFirst(2))
            // Matches subdomains (e.g. *.github.com matches api.github.com, sub.api.github.com)
            if h.hasSuffix("." + rootDomain) {
                return true
            }
            // Also matches the root domain itself (e.g. *.github.com matches github.com)
            if h == rootDomain {
                return true
            }
        }

        if pat.hasPrefix("*") {
            let suffix = String(pat.dropFirst())
            if h.hasSuffix(suffix) {
                return true
            }
        }

        return false
    }

    // MARK: - Target Extraction

    public func extractNetworkTargets(from output: AgentOutput) -> [NetworkTarget] {
        var targets: [NetworkTarget] = []

        // Inspect Tool Calls
        for toolCall in output.toolCalls {
            targets.append(contentsOf: extractTargets(from: toolCall))
        }

        // Inspect Content if enabled
        if config.inspectContent {
            targets.append(contentsOf: extractTargets(fromText: output.content, source: "agent_content"))
        }

        // Deduplicate targets by protocol + host + port
        var unique: [NetworkTarget] = []
        var seen = Set<String>()
        for target in targets {
            let key = "\(target.protocol.rawValue):\(target.host):\(target.port ?? 0)"
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(target)
            }
        }

        return unique
    }

    private func extractTargets(from toolCall: ToolCall) -> [NetworkTarget] {
        var targets: [NetworkTarget] = []
        let toolName = toolCall.name.lowercased()

        // 1. Dedicated network / fetch / curl tools
        if ["fetch", "curl", "http", "network", "web_search", "download", "websocket", "request"].contains(toolName) {
            for (_, value) in toolCall.arguments {
                if let str = value.unwrap() as? String {
                    targets.append(contentsOf: extractTargets(fromText: str, source: "tool:\(toolCall.name)"))
                }
            }
        }

        // 2. Shell / Bash tools
        if ["bash", "shell", "terminal", "exec", "sh", "zsh"].contains(toolName) {
            for (key, value) in toolCall.arguments {
                if ["command", "cmd", "script", "input"].contains(key.lowercased()),
                   let cmd = value.unwrap() as? String {
                    targets.append(contentsOf: extractTargets(fromBashCommand: cmd, source: "bash_cmd"))
                }
            }
        }

        return targets
    }

    public func extractTargets(fromBashCommand cmd: String, source: String = "bash_command") -> [NetworkTarget] {
        var targets: [NetworkTarget] = []

        // 1. Direct URLs in command
        targets.append(contentsOf: extractTargets(fromText: cmd, source: source))

        // 2. Tool invocations with host arguments: curl, wget, nc, netcat, ssh, scp, ping, git clone
        let lines = cmd.components(separatedBy: CharacterSet(charactersIn: "\n;&|"))
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let tokens = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard let firstToken = tokens.first?.lowercased() else { continue }
            let binary = (firstToken as NSString).lastPathComponent

            switch binary {
            case "curl", "wget", "wcurl", "aria2c":
                for token in tokens.dropFirst() {
                    if !token.hasPrefix("-") {
                        if let target = parseURLOrHost(token, defaultProtocol: .https, source: "\(source):\(binary)") {
                            targets.append(target)
                        }
                    }
                }

            case "nc", "netcat", "telnet", "socat":
                // nc [-options] host port
                let nonOptions = tokens.dropFirst().filter { !$0.hasPrefix("-") }
                if let host = nonOptions.first {
                    let port = nonOptions.count > 1 ? Int(nonOptions[1]) : nil
                    targets.append(NetworkTarget(
                        protocol: .tcp,
                        host: cleanHost(host),
                        port: port,
                        rawTarget: "\(host)\(port != nil ? ":\(port!)" : "")",
                        source: "\(source):\(binary)"
                    ))
                }

            case "ssh", "scp", "sftp":
                for token in tokens.dropFirst() {
                    if !token.hasPrefix("-") && token.contains("@") {
                        let parts = token.components(separatedBy: "@")
                        if let host = parts.last?.components(separatedBy: ":").first {
                            targets.append(NetworkTarget(
                                protocol: .ssh,
                                host: cleanHost(host),
                                port: 22,
                                rawTarget: token,
                                source: "\(source):\(binary)"
                            ))
                        }
                    }
                }

            case "git":
                // git clone <url>, git remote add <name> <url>, git fetch <url>
                for token in tokens.dropFirst() {
                    if token.hasPrefix("git@") || token.hasPrefix("http://") || token.hasPrefix("https://") || token.hasPrefix("ssh://") {
                        if let target = parseURLOrHost(token, defaultProtocol: .https, source: "\(source):git") {
                            targets.append(target)
                        }
                    }
                }

            case "ping", "traceroute", "nmap", "dig", "host", "nslookup":
                let nonOptions = tokens.dropFirst().filter { !$0.hasPrefix("-") }
                if let host = nonOptions.first {
                    targets.append(NetworkTarget(
                        protocol: binary == "dig" || binary == "nslookup" || binary == "host" ? .dns : .tcp,
                        host: cleanHost(host),
                        port: nil,
                        rawTarget: host,
                        source: "\(source):\(binary)"
                    ))
                }

            default:
                break
            }
        }

        return targets
    }

    public func extractTargets(fromText text: String, source: String = "text") -> [NetworkTarget] {
        var targets: [NetworkTarget] = []

        // Match URL schemes: http, https, ws, wss, tcp, ssh, ftp
        let urlPattern = #"(https?|wss?|tcp|ssh|ftp)://([a-zA-Z0-9.-]+)(?::([0-9]+))?(?:/[^\s"'`]*)?"#
        if let regex = try? NSRegularExpression(pattern: urlPattern, options: .caseInsensitive) {
            let nsText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

            for match in matches {
                guard match.numberOfRanges >= 3 else { continue }
                let schemeStr = nsText.substring(with: match.range(at: 1)).lowercased()
                let hostStr = nsText.substring(with: match.range(at: 2))
                let portStr: String? = match.range(at: 3).location != NSNotFound ? nsText.substring(with: match.range(at: 3)) : nil
                let rawMatch = nsText.substring(with: match.range)

                let proto = NetworkProtocol(rawValue: schemeStr) ?? .https
                let port = portStr.flatMap { Int($0) }

                targets.append(NetworkTarget(
                    protocol: proto,
                    host: cleanHost(hostStr),
                    port: port,
                    rawTarget: rawMatch,
                    source: source
                ))
            }
        }

        // Match SCP / SSH git style: git@github.com:user/repo.git
        let gitSshPattern = #"git@([a-zA-Z0-9.-]+):[^\s"'`]+"#
        if let regex = try? NSRegularExpression(pattern: gitSshPattern, options: .caseInsensitive) {
            let nsText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

            for match in matches {
                guard match.numberOfRanges >= 2 else { continue }
                let hostStr = nsText.substring(with: match.range(at: 1))
                let rawMatch = nsText.substring(with: match.range)

                targets.append(NetworkTarget(
                    protocol: .ssh,
                    host: cleanHost(hostStr),
                    port: 22,
                    rawTarget: rawMatch,
                    source: "\(source):git_ssh"
                ))
            }
        }

        return targets
    }

    private func parseURLOrHost(_ string: String, defaultProtocol: NetworkProtocol, source: String) -> NetworkTarget? {
        let cleaned = string.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`()[]{}"))
        guard !cleaned.isEmpty else { return nil }

        if let url = URL(string: cleaned), let scheme = url.scheme, let host = url.host {
            let proto = NetworkProtocol(rawValue: scheme.lowercased()) ?? defaultProtocol
            return NetworkTarget(
                protocol: proto,
                host: cleanHost(host),
                port: url.port,
                rawTarget: cleaned,
                source: source
            )
        }

        // Check if string looks like host:port or just hostname
        if cleaned.contains(".") && !cleaned.contains("/") {
            let parts = cleaned.components(separatedBy: ":")
            let host = parts[0]
            let port = parts.count > 1 ? Int(parts[1]) : nil
            return NetworkTarget(
                protocol: defaultProtocol,
                host: cleanHost(host),
                port: port,
                rawTarget: cleaned,
                source: source
            )
        }

        return nil
    }

    private func cleanHost(_ host: String) -> String {
        host.trimmingCharacters(in: CharacterSet(charactersIn: "[]\"'` \t\n\r/")).lowercased()
    }
}
