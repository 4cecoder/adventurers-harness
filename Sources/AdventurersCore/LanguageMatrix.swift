// LanguageMatrix.swift
// AdventurersCore — Hardcoded Polyglot Language Decision Engine
//
// Encodes deep architectural knowledge of which language is optimal for
// specific technical domains, latency envelopes, memory budgets, and targets.
//
// Pure Swift 6 · Sendable-safe

import Foundation

public enum LanguageTarget: String, Codable, Sendable, CaseIterable {
    case cOrZig = "C / Zig"
    case swift = "Swift 6"
    case python = "Python 3.11+ (uv)"
    case rust = "Rust"
    case shell = "Zsh / POSIX Shell"
}

public enum WorkloadDomain: String, Codable, Sendable, CaseIterable {
    case lowLatencyCompute = "low_latency_compute"
    case macosNativeSystem = "macos_native_system"
    case agentHarnessGlue = "agent_harness_glue"
    case networkSecurity = "network_security"
    case devopsOrchestration = "devops_orchestration"
}

public struct LanguageGuidance: Sendable {
    public let language: LanguageTarget
    public let rationale: String
    public let strengths: [String]
    public let cliVerificationMethod: String

    public init(language: LanguageTarget, rationale: String, strengths: [String], cliVerificationMethod: String) {
        self.language = language
        self.rationale = rationale
        self.strengths = strengths
        self.cliVerificationMethod = cliVerificationMethod
    }
}

public struct LanguageMatrix: Sendable {
    public static func guidance(for domain: WorkloadDomain) -> LanguageGuidance {
        switch domain {
        case .lowLatencyCompute:
            return LanguageGuidance(
                language: .cOrZig,
                rationale: "Zero-overhead deterministic memory, SIMD/Metal acceleration, and sub-millisecond execution.",
                strengths: ["Zero runtime allocations", "Direct POSIX ABI interop", "Raw hardware execution speed"],
                cliVerificationMethod: "Headless C assertions + AddressSanitizer (ASan)"
            )
        case .macosNativeSystem:
            return LanguageGuidance(
                language: .swift,
                rationale: "Apple Silicon unified memory performance, Sendable actor isolation, Metal 3, and AppKit integration.",
                strengths: ["Swift 6 strict concurrency checks", "Zero-copy Metal UMA buffers", "Direct OS PTY & Darwin bindings"],
                cliVerificationMethod: "`swift test` headless suite with 100% actor isolation"
            )
        case .agentHarnessGlue:
            return LanguageGuidance(
                language: .python,
                rationale: "High-speed iteration, dynamic AST manipulation, fast unit-synthesis loops, and Rich TUI telemetry.",
                strengths: ["Sub-second test execution via uv/pytest", "Rich interactive CLI visualizers", "Rapid mock & eval harness creation"],
                cliVerificationMethod: "Headless `uv run pytest` CLI test runner"
            )
        case .networkSecurity:
            return LanguageGuidance(
                language: .rust,
                rationale: "Compile-time memory safety, zero-cost abstractions, robust crypto/TLS crates, and high-concurrency daemons.",
                strengths: ["Guaranteed thread & memory safety", "Safe stream parsing", "Production-grade async Tokio runtime"],
                cliVerificationMethod: "`cargo test` headless runner + cargo audit"
            )
        case .devopsOrchestration:
            return LanguageGuidance(
                language: .shell,
                rationale: "Universal POSIX system control, git worktrees, process piping, and container lifecycle.",
                strengths: ["Native OS pipeline integration", "Universal mac/linux portability", "Zero dependency bootstrapping"],
                cliVerificationMethod: "Deterministic `set -euo pipefail` scripts + ShellCheck"
            )
        }
    }
}
