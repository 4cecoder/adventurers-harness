// GUI - Rich Seed Data for Testing and Development
// Provides realistic multi-turn threads, tool executions, diffs, and terminal sessions

import Foundation
import SwiftUI
import AdventurersCore

public enum SeedData {

    // MARK: - Sample Threads & Messages

    @MainActor
    public static func createPrimaryThreadViewModel() -> ThreadViewModel {
        let vm = ThreadViewModel()
        vm.messages = [
            ThreadMessage(
                role: .user,
                content: "We need to port the Darwin Seatbelt sandbox and deterministic gate certifications into pure Swift 6. Ensure we enforce the 3-tier security model (readOnly, workspaceWrite, dangerFullAccess) and prevent directory traversal attacks.",
                timestamp: Date().addingTimeInterval(-180)
            ),
            ThreadMessage(
                role: .agent,
                content: """
                I've analyzed the sandbox and certification requirements. We will implement:

                1. **Darwin Seatbelt Engine**: Direct Apple kernel profile generation using `import Darwin`.
                2. **3-Tier Security Policy**: `.readOnly`, `.workspaceWrite(workspaceRoot: URL)`, and `.dangerFullAccess`.
                3. **Path Traversal Validator**: Strict standardization preventing path escapes (`/etc/`, `~/.ssh/`).

                Let's inspect the existing protocol definitions and prepare the sandbox implementation.
                """,
                timestamp: Date().addingTimeInterval(-160),
                toolCalls: [
                    ThreadToolCall(
                        name: "ast_grep",
                        arguments: "{\"pattern\": \"protocol Tool\", \"path\": \"Sources/AdventurersCore/Protocols.swift\"}",
                        status: .succeeded(output: "Found protocol Tool: Sendable { ... } at Protocols.swift:10")
                    ),
                    ThreadToolCall(
                        name: "bash",
                        arguments: "{\"command\": \"swift test\"}",
                        status: .succeeded(output: "✔ Test run with 5 tests in 1 suite passed after 0.002s.")
                    )
                ],
                thinkingContent: "Examined Darwin kernel APIs. Verified that `sandbox_init` supports Scheme-based profiles. The AST check confirmed all gate interfaces are Sendable."
            ),
            ThreadMessage(
                role: .user,
                content: "Great. Now implement `DarwinSandbox.swift` and `DiffEngine.swift` with preflight hunk validation, and certify them against our Swift Testing test suites.",
                timestamp: Date().addingTimeInterval(-90)
            ),
            ThreadMessage(
                role: .agent,
                content: """
                I have implemented `DarwinSandbox.swift` and `DiffEngine.swift`:

                - **`DarwinSandbox`**: Generates Apple Seatbelt Scheme profiles with subpath whitelisting and validates path mutations.
                - **`DiffEngine`**: Preflights unified diffs to detect hunk conflicts and line mismatches before modifying disk.
                - **Swift Testing**: Added `@Test` coverage for both components. All 7 test suites are passing with zero warnings.

                ```swift
                let sandbox = DarwinSandbox.shared
                let isAllowed = await sandbox.validatePathAccess(
                    targetPath: "/Users/fource/workspace/test/file.swift",
                    mode: .workspaceWrite(workspaceRoot: workspace)
                )
                // Evaluates to true (locked inside workspace boundary)
                ```
                """,
                timestamp: Date().addingTimeInterval(-30),
                toolCalls: [
                    ThreadToolCall(
                        name: "diff_preflight",
                        arguments: "{\"file\": \"Sources/AdventurersCore/DarwinSandbox.swift\", \"hunks\": 3}",
                        status: .succeeded(output: "Preflight OK: 3 hunks matched with 0 conflicts.")
                    ),
                    ThreadToolCall(
                        name: "swift_test",
                        arguments: "{\"target\": \"AdventurersCoreTests\"}",
                        status: .succeeded(output: "✔ Test run with 7 tests in 1 suite passed after 0.002 seconds.")
                    )
                ],
                thinkingContent: "Verified path resolution against symbolic links and canonical paths. Confirmed DiffEngine properly raises conflict errors on dirty working trees."
            )
        ]

        // Populate certified gate state
        let pipeline = GatePipelineState()
        pipeline.passGate(.syntax, result: GateResult(passed: true, gateName: "SyntaxGate", output: "AST verified balanced"), elapsed: 0.005)
        pipeline.passGate(.repeatDetection, result: GateResult(passed: true, gateName: "RepeatGate", output: "0 duplicate loops detected"), elapsed: 0.001)
        pipeline.passGate(.compilation, result: GateResult(passed: true, gateName: "CompilationGate", output: "Clean compilation (0 errors)"), elapsed: 0.18)
        pipeline.passGate(.memory, result: GateResult(passed: true, gateName: "MemoryGate", output: "0 unbounded memory leaks"), elapsed: 0.002)
        pipeline.passGate(.objective, result: GateResult(passed: true, gateName: "ObjectiveGate", output: "Task contract fulfilled"), elapsed: 0.001)
        pipeline.allPassed = true
        vm.gateState = pipeline
        vm.isLoadingSkeleton = false

        return vm
    }

    @MainActor
    public static func createSecondaryThreadViewModel() -> ThreadViewModel {
        let vm = ThreadViewModel()
        vm.messages = [
            ThreadMessage(
                role: .user,
                content: "Audit memory allocations in the EventJournal actor during high-throughput round evaluations.",
                timestamp: Date().addingTimeInterval(-400)
            ),
            ThreadMessage(
                role: .agent,
                content: "Auditing `EventJournal.swift`. Evaluated ring-buffer allocations with 10,000 synthetic events. Memory usage is steady at ~2.4MB with zero retain cycles.",
                timestamp: Date().addingTimeInterval(-320),
                toolCalls: [
                    ThreadToolCall(
                        name: "memory_audit",
                        arguments: "{\"actor\": \"EventJournal\", \"iterations\": 10000}",
                        status: .succeeded(output: "Peak memory: 2.4 MB, Zero leak rate detected.")
                    )
                ]
            )
        ]

        let pipeline = GatePipelineState()
        pipeline.passGate(.syntax, result: GateResult(passed: true, gateName: "SyntaxGate", output: "Passed"), elapsed: 0.001)
        pipeline.passGate(.repeatDetection, result: GateResult(passed: true, gateName: "RepeatGate", output: "Passed"), elapsed: 0.001)
        pipeline.passGate(.compilation, result: GateResult(passed: true, gateName: "CompilationGate", output: "Passed"), elapsed: 0.12)
        pipeline.passGate(.memory, result: GateResult(passed: true, gateName: "MemoryGate", output: "Passed"), elapsed: 0.004)
        pipeline.passGate(.objective, result: GateResult(passed: true, gateName: "ObjectiveGate", output: "Passed"), elapsed: 0.001)
        pipeline.allPassed = true
        vm.gateState = pipeline
        vm.isLoadingSkeleton = false

        return vm
    }

    // MARK: - Sample Diffs

    @MainActor
    public static func createRichDiffState() -> DiffViewerState {
        let lines1: [DiffLine] = [
            DiffLine(type: .context, content: "import Foundation", oldLineNum: 1, newLineNum: 1),
            DiffLine(type: .addition, content: "import Darwin", oldLineNum: nil, newLineNum: 2),
            DiffLine(type: .context, content: "", oldLineNum: 2, newLineNum: 3),
            DiffLine(type: .deletion, content: "// Legacy Unchecked Sandbox Mode", oldLineNum: 3, newLineNum: nil),
            DiffLine(type: .addition, content: "// MARK: - Sandbox Mode", oldLineNum: nil, newLineNum: 4),
            DiffLine(type: .addition, content: "public enum SandboxMode: Sendable, Equatable {", oldLineNum: nil, newLineNum: 5),
            DiffLine(type: .addition, content: "    case readOnly", oldLineNum: nil, newLineNum: 6),
            DiffLine(type: .addition, content: "    case workspaceWrite(workspaceRoot: URL, additionalAllowedRoots: [URL] = [])", oldLineNum: nil, newLineNum: 7),
            DiffLine(type: .addition, content: "    case dangerFullAccess", oldLineNum: nil, newLineNum: 8),
            DiffLine(type: .addition, content: "}", oldLineNum: nil, newLineNum: 9),
            DiffLine(type: .context, content: "", oldLineNum: 4, newLineNum: 10),
            DiffLine(type: .context, content: "public actor DarwinSandbox {", oldLineNum: 5, newLineNum: 11),
            DiffLine(type: .addition, content: "    public static let shared = DarwinSandbox()", oldLineNum: nil, newLineNum: 12),
            DiffLine(type: .addition, content: "    public func generateSeatbeltProfile(for mode: SandboxMode) -> String { ... }", oldLineNum: nil, newLineNum: 13),
            DiffLine(type: .context, content: "}", oldLineNum: 6, newLineNum: 14)
        ]

        let hunk1 = DiffHunk(
            header: "@@ -1,6 +1,14 @@ public actor DarwinSandbox {",
            oldStart: 1,
            oldCount: 6,
            newStart: 1,
            newCount: 14,
            lines: lines1
        )

        let file1 = DiffFile(
            filePath: "Sources/AdventurersCore/DarwinSandbox.swift",
            language: .swift,
            hunks: [hunk1]
        )

        let lines2: [DiffLine] = [
            DiffLine(type: .addition, content: "import Foundation", oldLineNum: nil, newLineNum: 1),
            DiffLine(type: .addition, content: "", oldLineNum: nil, newLineNum: 2),
            DiffLine(type: .addition, content: "public final class DiffEngine: Sendable {", oldLineNum: nil, newLineNum: 3),
            DiffLine(type: .addition, content: "    public static let shared = DiffEngine()", oldLineNum: nil, newLineNum: 4),
            DiffLine(type: .addition, content: "    public func parseUnifiedDiff(_ rawDiff: String) -> [FilePatch] { ... }", oldLineNum: nil, newLineNum: 5),
            DiffLine(type: .addition, content: "    public func preflight(originalContent: String, hunks: [DiffHunk]) -> PreflightResult { ... }", oldLineNum: nil, newLineNum: 6),
            DiffLine(type: .addition, content: "    public func apply(originalContent: String, hunks: [DiffHunk]) throws -> String { ... }", oldLineNum: nil, newLineNum: 7),
            DiffLine(type: .addition, content: "}", oldLineNum: nil, newLineNum: 8)
        ]

        let hunk2 = DiffHunk(
            header: "@@ -0,0 +1,8 @@",
            oldStart: 0,
            oldCount: 0,
            newStart: 1,
            newCount: 8,
            lines: lines2
        )

        let file2 = DiffFile(
            filePath: "Sources/AdventurersCore/DiffEngine.swift",
            language: .swift,
            hunks: [hunk2]
        )

        return DiffViewerState(files: [file1, file2])
    }
}
