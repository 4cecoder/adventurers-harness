"""
Adventurers Polyglot Language Selector & Decision Matrix
Hardcoded architectural knowledge encoding which programming languages are best suited
for specific subsystems, latency envelopes, memory budgets, and platform targets.
"""

from enum import Enum
from typing import Dict, List
from pydantic import BaseModel


class Language(str, Enum):
    C_ZIG = "C / Zig"
    SWIFT = "Swift (Swift 6)"
    PYTHON = "Python (uv)"
    RUST = "Rust"
    SHELL = "Zsh / POSIX Shell"


class WorkloadDomain(str, Enum):
    LOW_LATENCY_COMPUTE = (
        "low_latency_compute"  # Tokenizers, SIMD math, byte parsing, zero-alloc buffers
    )
    MACOS_NATIVE_SYSTEM = (
        "macos_native_system"  # PTY, Metal shaders, AppKit/SwiftUI, OS permissions
    )
    AGENT_HARNESS_GLUE = (
        "agent_harness_glue"  # Deterministic synthesis loops, eval harnesses, test runners
    )
    NETWORK_SECURITY = "network_security"  # Sandboxing, TLS interception, memory-safe parsing
    DEVOPS_ORCHESTRATION = "devops_orchestration"  # Git worktrees, process piping, Docker compose


class LanguageRecommendation(BaseModel):
    selected_language: Language
    rationale: str
    strengths: List[str]
    best_tooling: str
    verification_methodology: str


# Hardcoded Architectural Knowledge Matrix
LANGUAGE_DECISION_MATRIX: Dict[WorkloadDomain, LanguageRecommendation] = {
    WorkloadDomain.LOW_LATENCY_COMPUTE: LanguageRecommendation(
        selected_language=Language.C_ZIG,
        rationale="Zero overhead, deterministic memory layout, SIMD/Metal acceleration, and sub-millisecond execution.",
        strengths=[
            "Deterministic zero-alloc memory",
            "Direct POSIX/C ABI interop",
            "Raw hardware execution speed",
        ],
        best_tooling="Clang / Zig compiler with strict -Wall -Wextra -Werror",
        verification_methodology="C assert unit tests + Valgrind / AddressSanitizer (ASan) memory safety checks",
    ),
    WorkloadDomain.MACOS_NATIVE_SYSTEM: LanguageRecommendation(
        selected_language=Language.SWIFT,
        rationale="Bespoke Apple Silicon performance, native Sendable concurrency, Metal 3 unified memory, and macOS entitlements.",
        strengths=[
            "Swift 6 strict concurrency checks",
            "Direct AppKit/Foundation/PTY bindings",
            "Zero-copy Metal UMA buffers",
        ],
        best_tooling="Swift Package Manager (spm) + swift-testing + Instruments",
        verification_methodology="`swift test` headless suite with 100% actor-isolation safety",
    ),
    WorkloadDomain.AGENT_HARNESS_GLUE: LanguageRecommendation(
        selected_language=Language.PYTHON,
        rationale="Fast iteration, rich AST manipulation, headless CLI benchmarking, and rich terminal telemetry.",
        strengths=[
            "Sub-second test execution with uv/pytest",
            "Dynamic code evaluation & string manipulation",
            "Rich interactive CLI visualizers",
        ],
        best_tooling="uv (fast C-based Python package manager) + Pytest + Rich TUI",
        verification_methodology="Headless `uv run pytest` CLI test suites verifying function contracts",
    ),
    WorkloadDomain.NETWORK_SECURITY: LanguageRecommendation(
        selected_language=Language.RUST,
        rationale="Compile-time memory safety, zero-cost abstractions, robust crypto/TLS crates, and high-concurrency async daemons.",
        strengths=[
            "Guaranteed thread safety & memory safety",
            "Safe byte stream parsing",
            "Production-grade async Tokio runtime",
        ],
        best_tooling="Cargo + clippy + miri",
        verification_methodology="`cargo test` headless runner + cargo audit for supply chain security",
    ),
    WorkloadDomain.DEVOPS_ORCHESTRATION: LanguageRecommendation(
        selected_language=Language.SHELL,
        rationale="Universal POSIX environment control, git worktree lifecycle, subprocess piping, and container bootstrapping.",
        strengths=[
            "Native OS shell integration",
            "Standard Unix pipeline composition",
            "Universal portability across mac/linux",
        ],
        best_tooling="zsh / bash with `set -euo pipefail` + ShellCheck",
        verification_methodology="Deterministic bats / shunit2 script assertion tests",
    ),
}


def recommend_language_for_task(domain: WorkloadDomain) -> LanguageRecommendation:
    """Returns the optimal language recommendation for a given technical domain."""
    return LANGUAGE_DECISION_MATRIX[domain]


def classify_prompt_domain(prompt: str) -> WorkloadDomain:
    """Classifies user intent or coding objective into the optimal language domain."""
    prompt_lower = prompt.lower()

    if any(
        k in prompt_lower
        for k in ("docker", "compose", "git worktree", "submodule", "sh script", "bash")
    ):
        return WorkloadDomain.DEVOPS_ORCHESTRATION
    elif any(
        k in prompt_lower for k in ("metal", "uma", "appkit", "swiftui", "macos", "pty", "sendable")
    ):
        return WorkloadDomain.MACOS_NATIVE_SYSTEM
    elif any(
        k in prompt_lower
        for k in ("simd", "zero-alloc", "c code", "zig", "byte parser", "bit packing", "1-bit")
    ):
        return WorkloadDomain.LOW_LATENCY_COMPUTE
    elif any(k in prompt_lower for k in ("tls", "proxy", "crypto", "sandbox kernel", "rust")):
        return WorkloadDomain.NETWORK_SECURITY
    else:
        # Default agentic logic, CLI tooling, test synthesis
        return WorkloadDomain.AGENT_HARNESS_GLUE
