// NeedleProcessorTests.swift
// Adventurers Harness — Unit Tests for Cactus Needle 2 Fast-Path Processing & Compaction

import Testing
import Foundation
@testable import AdventurersCore

@Suite("Cactus Needle 2 Local Intelligence & Compactor Suite")
struct NeedleProcessorTests {

    @Test("Needle 2 routes explicit test commands to instant local tool execution")
    func testTestCommandRouting() {
        let processor = NeedleProcessor()
        let decision = processor.process(prompt: "run test suite")

        #expect(decision.confidence >= 0.90)
        #expect(decision.tokenSavingsEstimated > 0)
        if case .localFastExecute(let tool, let args) = decision.mode {
            #expect(tool == "run_command")
            #expect(args["command"]?.contains("swift test") == true)
        } else {
            Issue.record("Expected local fast execute for test command")
        }
    }

    @Test("Needle 2 routes git status and git diff to fast local execution")
    func testGitRouting() {
        let processor = NeedleProcessor()

        let statusDecision = processor.process(prompt: "git status")
        if case .localFastExecute(let tool, let args) = statusDecision.mode {
            #expect(tool == "run_command")
            #expect(args["command"]?.contains("git status") == true)
        } else {
            Issue.record("Expected git status fast execution")
        }

        let diffDecision = processor.process(prompt: "show diff")
        if case .localFastExecute(let tool, let args) = diffDecision.mode {
            #expect(tool == "run_command")
            #expect(args["command"]?.contains("git diff") == true)
        } else {
            Issue.record("Expected git diff fast execution")
        }
    }

    @Test("Needle 2 routes grep pattern searches with extracted query argument")
    func testGrepSearchRouting() {
        let processor = NeedleProcessor()
        let decision = processor.process(prompt: "search for NeedleProcessor")

        if case .localFastExecute(let tool, let args) = decision.mode {
            #expect(tool == "grep_search")
            #expect(args["query"] == "NeedleProcessor")
        } else {
            Issue.record("Expected grep_search with query NeedleProcessor")
        }
    }

    @Test("Needle 2 escalates open-ended reasoning prompts to cloud model")
    func testCloudEscalation() {
        let processor = NeedleProcessor()
        let decision = processor.process(prompt: "Can you design a distributed CRDT synchronization protocol for multi-user collaboration?")

        #expect(decision.confidence < 0.80)
        if case .cloudEscalate(let reason) = decision.mode {
            #expect(!reason.isEmpty)
        } else {
            Issue.record("Expected cloud escalation for complex reasoning query")
        }
    }

    @Test("Needle 2 Compactor condenses verbose compiler output to key errors and warnings")
    func testBuildLogCompactor() {
        var rawLog = ""
        for i in 1...100 {
            rawLog += "Compiling Module File\(i).swift\n"
        }
        rawLog += "/Sources/App.swift:42:10: error: cannot find 'InvalidSymbol' in scope\n"
        rawLog += "/Sources/App.swift:55:12: warning: variable 'temp' was never mutated\n"
        for i in 101...150 {
            rawLog += "Linking binary step \(i)...\n"
        }

        let compacted = NeedleOutputCompactor.compactBuildLog(rawLog)
        #expect(compacted.contains("Needle 2 Compactor"))
        #expect(compacted.contains("cannot find 'InvalidSymbol'"))
        #expect(compacted.contains("variable 'temp' was never mutated"))
        #expect(compacted.count < rawLog.count)
    }

    @Test("Needle 2 Diff Compactor summarizes multi-file diff hunks")
    func testDiffCompactor() {
        var rawDiff = ""
        for file in ["A", "B", "C"] {
            rawDiff += "diff --git a/\(file).swift b/\(file).swift\n"
            rawDiff += "--- a/\(file).swift\n"
            rawDiff += "+++ b/\(file).swift\n"
            rawDiff += "@@ -1,5 +1,6 @@\n"
            for _ in 1...40 {
                rawDiff += "+ let item = 123\n"
            }
        }

        let compacted = NeedleOutputCompactor.compactDiff(rawDiff)
        #expect(compacted.contains("Needle 2 Diff Compactor"))
        #expect(compacted.contains("📁 diff --git"))
    }

    @Test("Needle 2 routes build commands to swift build")
    func testBuildRouting() {
        let processor = NeedleProcessor()
        let decision = processor.process(prompt: "swift build")

        #expect(decision.confidence >= 0.90)
        if case .localFastExecute(let tool, let args) = decision.mode {
            #expect(tool == "run_command")
            #expect(args["command"] == "swift build")
        } else {
            Issue.record("Expected swift build fast execution")
        }
    }

    @Test("Needle 2 routes file creation commands to write_to_file")
    func testFileCreationRouting() {
        let processor = NeedleProcessor()
        let decision = processor.process(prompt: "create a new file called CHANGELOG.md")

        #expect(decision.confidence >= 0.90)
        if case .localFastExecute(let tool, let args) = decision.mode {
            #expect(tool == "write_to_file")
            #expect(args["path"] == "CHANGELOG.md")
        } else {
            Issue.record("Expected write_to_file for CHANGELOG.md")
        }
    }

    @Test("Needle 2 extracts explicit file path for direct viewing")
    func testExplicitFileViewing() {
        let processor = NeedleProcessor()
        let decision = processor.process(prompt: "show me Package.swift")

        #expect(decision.confidence >= 0.90)
        if case .localFastExecute(let tool, let args) = decision.mode {
            #expect(tool == "view_file")
            #expect(args["path"] == "Package.swift")
        } else {
            Issue.record("Expected view_file for Package.swift")
        }
    }

    @Test("Needle 2 extracts structured contact record directly")
    func testStructuredContactExtraction() {
        let processor = NeedleProcessor()
        let decision = processor.process(prompt: "extract contact: Reach out to Alex Chen at alex.chen@example.com about the PR.")

        #expect(decision.confidence >= 0.90)
        if case .directStructuredResponse(let json) = decision.mode {
            #expect(json.contains("alex.chen@example.com"))
            #expect(json.contains("Alex Chen"))
        } else {
            Issue.record("Expected directStructuredResponse for contact extraction")
        }
    }

    @Test("Needle 2 categorizes bug report locally")
    func testCategorizeBug() {
        let processor = NeedleProcessor()
        let decision = processor.process(prompt: "categorize item: app crashes on launch when no API key is set")

        #expect(decision.confidence >= 0.90)
        if case .directStructuredResponse(let json) = decision.mode {
            #expect(json.contains("BUG"))
        } else {
            Issue.record("Expected BUG categorization")
        }
    }
}
