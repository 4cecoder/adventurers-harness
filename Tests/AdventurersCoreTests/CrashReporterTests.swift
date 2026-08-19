// CrashReporterTests.swift
// AdventurersCoreTests — Unit Tests for Native Crash Diagnostic Engine

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

    @Test("CrashReporterManager tracks rolling breadcrumbs and limits capacity")
    func breadcrumbTracking() {
        let manager = CrashReporterManager.shared
        manager.addBreadcrumb("Event 1: Application Launched")
        manager.addBreadcrumb("Event 2: Workspace Selected")

        let breadcrumbs = manager.recentBreadcrumbs
        #expect(breadcrumbs.contains { $0.contains("Event 1: Application Launched") })
        #expect(breadcrumbs.contains { $0.contains("Event 2: Workspace Selected") })
    }

    @Test("CrashReporterManager saves report and retrieves from disk")
    func saveAndListCrashReports() {
        let manager = CrashReporterManager.shared
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
