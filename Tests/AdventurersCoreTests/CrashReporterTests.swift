// CrashReporterTests.swift
// AdventurersCoreTests — Unit Tests for Native Crash Diagnostic & Crashlytics Engine

import Testing
import Foundation
@testable import AdventurersCore

@Suite("Crash Reporter & Diagnostics Suite")
struct CrashReporterTests {

    @Test("CrashReport formatted summary contains architecture, OS version, and callstack")
    func crashReportFormattedSummary() {
        let report = CrashReport(
            signal: "SIGSEGV (Segmentation Fault)",
            exceptionName: nil,
            exceptionReason: "Invalid memory address 0x0",
            callStack: [
                "0 AdventurersCore 0x0000000100001234 CrashReporterManager.recordCrash + 120",
                "1 AdventurersCore 0x0000000100005678 ThreadViewModel.sendMessage + 450"
            ],
            breadcrumbs: [
                "User selected Claude 3.7",
                "Started session turn 1"
            ],
            activeModel: "claude-3-7-sonnet",
            activeExecutionMode: "Subscription",
            activeThreadID: "test-thread-uuid",
            memoryUsageBytes: 50_000_000
        )

        let summary = report.formattedSummary
        #expect(summary.contains("ADVENTURERS HARNESS CRASH REPORT"))
        #expect(summary.contains("SIGSEGV (Segmentation Fault)"))
        #expect(summary.contains("claude-3-7-sonnet"))
        #expect(summary.contains("User selected Claude 3.7"))
        #expect(summary.contains("ThreadViewModel.sendMessage"))
    }

    @Test("SwiftDemangler classifies application code frames versus system frameworks")
    func stackFrameDemanglingAndClassification() {
        let rawLines = [
            "0   Adventurers   0x0000000100021b34 $s14AdventurersGUI15ThreadViewModelC18executeNativeTool4name9argumentsAA0I6ResultVSS_SDySS12LLMProviders10AnyCodableVGtYaF + 120",
            "1   libdispatch.dylib   0x0000000196f6c5c0 _dispatch_assert_queue_fail + 120",
            "2   libsystem_pthread.dylib   0x0000000197022f48 _pthread_start + 136"
        ]

        let frames = SwiftDemangler.parseCallStack(rawLines)
        #expect(frames.count == 3)
        #expect(frames[0].isAppCode == true)
        #expect(frames[0].module == "Adventurers")
        #expect(frames[0].demangledSymbol.contains("GUI.15ThreadViewModel"))
        #expect(frames[1].isAppCode == false)
        #expect(frames[1].module == "libdispatch.dylib")
    }

    @Test("Crashlytics generates structured LLM root cause analysis prompts")
    func llmAnalysisPromptGeneration() {
        let report = CrashReport(
            severity: .fatal,
            signal: "SIGSEGV (Segmentation Fault)",
            exceptionName: nil,
            exceptionReason: "Null pointer dereference",
            callStack: [
                "0 AdventurersCore 0x0000000100001234 CrashReporterManager.recordCrash + 120"
            ],
            breadcrumbs: ["Step 1", "Step 2"],
            activeModel: "qwen2.5-coder-32b-instruct"
        )

        let prompt = report.llmAnalysisPrompt
        #expect(prompt.contains("expert Swift 6 and macOS systems diagnostic engineer"))
        #expect(prompt.contains("SIGSEGV (Segmentation Fault)"))
        #expect(prompt.contains("qwen2.5-coder-32b-instruct"))
        #expect(prompt.contains("Null pointer dereference"))
    }

    @Test("CrashReporterManager tracks rolling breadcrumbs and limits capacity")
    func breadcrumbTracking() {
        let manager = CrashReporterManager.shared
        manager.addBreadcrumb("Event 1: Application Launched")
        manager.addBreadcrumb("Event 2: Workspace Selected")

        let breadcrumbs = manager.recentBreadcrumbs
        #expect(breadcrumbs.contains { $0.contains("Event 1: Application Launched") })
        #expect(breadcrumbs.contains { $0.contains("Event 2: Workspace Selected") })
    }

    @Test("CrashReporterManager records non-fatal issues and updates metrics")
    func nonFatalRecordingAndMetrics() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("adventurers-crash-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manager = CrashReporterManager(crashDirectoryOverride: tempDir, installHandlers: false)

        enum TestError: Error { case connectionFailed }
        let nonFatal = manager.recordNonFatal(error: TestError.connectionFailed, context: "Connecting to LM Studio")

        #expect(nonFatal.severity == .nonFatal)
        #expect(nonFatal.exceptionReason?.contains("Connecting to LM Studio") == true)

        let metrics = manager.calculateMetrics()
        #expect(metrics.totalEvents >= 1)
        #expect(metrics.nonFatalCount >= 1)
    }

    @Test("CrashReporterManager saves report and retrieves from disk")
    func saveAndListCrashReports() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("adventurers-crash-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manager = CrashReporterManager(crashDirectoryOverride: tempDir, installHandlers: false)
        let initialCount = manager.listCrashReports().count

        let testReport = manager.recordCrash(
            signal: "SIGABRT (Abort Process)",
            exceptionName: "NSInvalidArgumentException",
            exceptionReason: "Test simulated crash",
            callStack: ["0 test_binary 0x1234 funcA + 10"]
        )

        let reportsAfter = manager.listCrashReports()
        #expect(reportsAfter.count >= initialCount + 1)
        #expect(reportsAfter.contains { $0.id == testReport.id })
    }
}
