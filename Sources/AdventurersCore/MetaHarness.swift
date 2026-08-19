// MetaHarness.swift
// AdventurersCore — Execution Mode & Meta-Harness Multi-Agent CLI Dispatcher
//
// Pure Swift 6 · Sendable-safe

import Foundation

// MARK: - Execution Mode

public enum ExecutionMode: String, CaseIterable, Sendable, Codable {
    /// Direct LLM Provider execution for code synthesis, planning, and tool calling
    case codingPlan = "Coding Plan (Direct LLM)"
    /// Delegated execution to external sub-harness CLIs (Codex, Hermes, OpenCode, DeepSeek Harness, etc.)
    case metaHarness = "Meta Harness (External CLIs)"

    public var shortLabel: String {
        switch self {
        case .codingPlan: return "Coding Plan"
        case .metaHarness: return "Meta Harness"
        }
    }

    public var icon: String {
        switch self {
        case .codingPlan: return "bolt.shield.fill"
        case .metaHarness: return "arrow.triangle.branch"
        }
    }

    public var description: String {
        switch self {
        case .codingPlan:
            return "Direct API streaming with native gate certification, token compression, and local tool execution."
        case .metaHarness:
            return "Delegates prompts and tasks to external specialized agent harness binaries with isolated API keys and environments."
        }
    }
}

// MARK: - Meta Harness Types

public enum MetaHarnessType: String, CaseIterable, Sendable, Codable, Identifiable {
    public var id: String { rawValue }

    case antigravity = "Google Antigravity CLI (agy)"
    case claudeCode = "Anthropic Claude Code CLI (claude)"
    case codex = "OpenAI Codex CLI"
    case hermes = "Nous Hermes Agent"
    case opencode = "OpenCode CLI"
    case muse = "Meta Muse Code (muse)"
    case deepseekHarness = "DeepSeek Harness (dsh)"
    case pi = "Pi Agent Harness"
    case smallctl = "SmallCTL (FAMA)"
    case custom = "Custom External Harness"

    public var icon: String {
        switch self {
        case .antigravity: return "atom"
        case .claudeCode: return "brain.head.profile"
        case .codex: return "cpu"
        case .hermes: return "sparkles"
        case .opencode: return "terminal.fill"
        case .muse: return "sparkles.rectangle.stack"
        case .deepseekHarness: return "bolt.fill"
        case .pi: return "number"
        case .smallctl: return "shield.lefthalf.filled"
        case .custom: return "wrench.and.screwdriver"
        }
    }

    public var defaultBinaryName: String {
        switch self {
        case .antigravity: return "agy"
        case .claudeCode: return "claude"
        case .codex: return "codex"
        case .hermes: return "hermes"
        case .opencode: return "opencode"
        case .muse: return "muse"
        case .deepseekHarness: return "dsh"
        case .pi: return "pi"
        case .smallctl: return "smallctl"
        case .custom: return "agent-harness"
        }
    }

    public var defaultEnvKeyName: String {
        switch self {
        case .antigravity: return "GEMINI_API_KEY"
        case .claudeCode: return "ANTHROPIC_API_KEY"
        case .codex: return "CODEX_API_KEY"
        case .hermes: return "HERMES_API_KEY"
        case .opencode: return "OPENCODE_API_KEY"
        case .muse: return "META_API_KEY"
        case .deepseekHarness: return "DEEPSEEK_API_KEY"
        case .pi: return "PI_API_KEY"
        case .smallctl: return "OPENAI_API_KEY"
        case .custom: return "AGENT_API_KEY"
        }
    }

    public var description: String {
        switch self {
        case .antigravity:
            return "Google Antigravity CLI (agy) featuring multi-agent swarms, brain/artifacts system, skill execution, MCP servers, and subagent orchestration."
        case .claudeCode:
            return "Anthropic Claude Code CLI with interactive terminal agent capabilities, fast codebase exploration, subagent architecture, and git integration."
        case .codex:
            return "Rust-based gate-certified execution engine with native LSP support and deterministic contracts."
        case .hermes:
            return "Staged reflection agent featuring persistent episodic memory and trajectory learning loop."
        case .opencode:
            return "Go-based multi-provider coding agent with SQLite session state and AST validation."
        case .muse:
            return "Meta Muse Code terminal agent featuring whole-repository generation, 1M context window, multi-agent workflows, and Muse Spark 1.2 models."
        case .deepseekHarness:
            return "Plugin-everything modular harness designed for frontier DeepSeek reasoning models."
        case .pi:
            return "TypeScript multi-provider interactive coding and autonomous exploration harness."
        case .smallctl:
            return "FAMA staged failure mitigation harness optimized for small and medium-sized coding models."
        case .custom:
            return "User-configured external CLI agent or executable runner."
        }
    }
}

// MARK: - Meta Harness Authentication Mode

/// Authentication strategy for external agent CLIs (e.g. OpenCode, Hermes, Claude, Antigravity)
public enum MetaHarnessAuthMode: String, CaseIterable, Sendable, Codable, Identifiable {
    public var id: String { rawValue }

    /// CLI manages its own subscription, token cache, or browser OAuth session (e.g. `opencode auth login`, `claude login`, `agy` token)
    case nativeSubscription = "CLI Native Plan / OAuth Subscription"
    /// Injected API key passed via environment variable (e.g. `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`)
    case injectedApiKey = "Injected Environment API Key"
    /// Hybrid auto-detect: utilizes local auth session if logged in, otherwise injects configured API key
    case hybrid = "Hybrid (Native Session with Key Fallback)"

    public var icon: String {
        switch self {
        case .nativeSubscription: return "creditcard.fill"
        case .injectedApiKey: return "key.fill"
        case .hybrid: return "arrow.triangle.2.circlepath.circle.fill"
        }
    }
}

// MARK: - Meta Harness Profile

public struct MetaHarnessProfile: Identifiable, Sendable, Codable {
    public var id: String { type.rawValue }
    public let type: MetaHarnessType
    public var binaryPath: String
    public var apiKey: String
    public var authMode: MetaHarnessAuthMode
    public var customArgs: [String]
    public var envVars: [String: String]
    public var isEnabled: Bool
    public var autoDetected: Bool

    public init(
        type: MetaHarnessType,
        binaryPath: String = "",
        apiKey: String = "",
        authMode: MetaHarnessAuthMode = .hybrid,
        customArgs: [String] = [],
        envVars: [String: String] = [:],
        isEnabled: Bool = true,
        autoDetected: Bool = false
    ) {
        self.type = type
        self.binaryPath = binaryPath.isEmpty ? type.defaultBinaryName : binaryPath
        self.apiKey = apiKey
        self.authMode = authMode
        self.customArgs = customArgs
        self.envVars = envVars
        self.isEnabled = isEnabled
        self.autoDetected = autoDetected
    }
}

// MARK: - Meta Harness Registry & CLI Discovery

public final class MetaHarnessRegistry: Sendable {
    public static let shared = MetaHarnessRegistry()

    public init() {}

    /// Auto-discovers installed Meta Harness binaries on the system ($PATH, /opt/homebrew, ~/.local/bin, research/)
    public func discoverProfiles(existing: [MetaHarnessProfile] = []) -> [MetaHarnessProfile] {
        var results: [MetaHarnessProfile] = []
        let fm = FileManager.default
        let pathDirs = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .components(separatedBy: ":") + [
                "/opt/homebrew/bin",
                "/usr/local/bin",
                "\(fm.homeDirectoryForCurrentUser.path)/.local/bin",
                "\(fm.homeDirectoryForCurrentUser.path)/.cargo/bin",
                "\(fm.currentDirectoryPath)/research"
            ]

        for type in MetaHarnessType.allCases {
            // Check if existing profile has user customization
            let existingProfile = existing.first(where: { $0.type == type })

            var detectedPath = ""
            var isFound = false

            // Search for executable
            for dir in pathDirs {
                let candidate = (dir as NSString).appendingPathComponent(type.defaultBinaryName)
                if fm.isExecutableFile(atPath: candidate) {
                    detectedPath = candidate
                    isFound = true
                    break
                }
            }

            if var p = existingProfile {
                if !isFound && p.binaryPath.isEmpty {
                    p.binaryPath = type.defaultBinaryName
                }
                if isFound && (p.binaryPath == type.defaultBinaryName || p.binaryPath.isEmpty) {
                    p.binaryPath = detectedPath
                    p.autoDetected = true
                }
                results.append(p)
            } else {
                let newProfile = MetaHarnessProfile(
                    type: type,
                    binaryPath: isFound ? detectedPath : type.defaultBinaryName,
                    apiKey: "",
                    customArgs: [],
                    envVars: [:],
                    isEnabled: isFound,
                    autoDetected: isFound
                )
                results.append(newProfile)
            }
        }

        return results
    }
}

// MARK: - Meta Harness Runner (Process Subprocess Invoker)

public final class MetaHarnessRunner: Sendable {
    public static let shared = MetaHarnessRunner()

    public init() {}

    /// Runs an external meta-harness CLI with isolated credentials and environment variables, streaming output deltas
    public func executeHarness(
        profile: MetaHarnessProfile,
        prompt: String,
        workspacePath: String,
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws -> Int {
        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
        
        // Inject dedicated Meta-Harness API Key if enabled and configured
        if profile.authMode != .nativeSubscription && !profile.apiKey.isEmpty {
            env[profile.type.defaultEnvKeyName] = profile.apiKey
            // Also set common fallbacks if applicable
            env["OPENAI_API_KEY"] = profile.apiKey
            env["ANTHROPIC_API_KEY"] = profile.apiKey
            env["DEEPSEEK_API_KEY"] = profile.apiKey
            env["GEMINI_API_KEY"] = profile.apiKey
        }

        // Custom environment variables
        for (k, v) in profile.envVars {
            env[k] = v
        }

        process.environment = env
        process.currentDirectoryURL = URL(fileURLWithPath: workspacePath)

        let escapedPrompt = prompt.replacingOccurrences(of: "'", with: "'\\''")
        let customArgsJoined = profile.customArgs.joined(separator: " ")
        
        let commandLine: String
        if !customArgsJoined.isEmpty {
            commandLine = "\(profile.binaryPath) \(customArgsJoined) '\(escapedPrompt)'"
        } else {
            switch profile.type {
            case .claudeCode, .antigravity, .hermes:
                commandLine = "\(profile.binaryPath) -p '\(escapedPrompt)'"
            case .muse:
                commandLine = "\(profile.binaryPath) exec --json '\(escapedPrompt)'"
            default:
                commandLine = "\(profile.binaryPath) '\(escapedPrompt)'"
            }
        }

        process.arguments = ["-c", commandLine]
        process.standardOutput = pipe
        process.standardError = errorPipe

        let outHandle = pipe.fileHandleForReading
        let errHandle = errorPipe.fileHandleForReading

        outHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            onOutput(text)
        }

        errHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            onOutput(text)
        }

        try process.run()
        ActiveProcessRegistry.shared.register(process: process)
        defer {
            ActiveProcessRegistry.shared.unregister(process: process)
            outHandle.readabilityHandler = nil
            errHandle.readabilityHandler = nil
        }

        while process.isRunning {
            if Task.isCancelled {
                ActiveProcessRegistry.shared.killProcess(process)
                break
            }
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        return Int(process.terminationStatus)
    }
}
