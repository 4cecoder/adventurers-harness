// CrashReporter.swift
// AdventurersCore — Native Crash Diagnostic & Backtrace Reporting Engine
// Captures POSIX signals, NSExceptions, thread callstacks, breadcrumbs, and macOS DiagnosticReports
//
// Pure Swift 6 · Sendable-safe

import Foundation
import os.lock

// MARK: - Crash Report Model

public struct CrashReport: Codable, Identifiable, Sendable {
    public let id: String
    public let timestamp: Date
    public let signal: String?
    public let exceptionName: String?
    public let exceptionReason: String?
    public let callStack: [String]
    public let breadcrumbs: [String]
    public let activeModel: String?
    public let activeExecutionMode: String?
    public let activeThreadID: String?
    public let memoryUsageBytes: UInt64
    public let osVersion: String
    public let appVersion: String
    public let architecture: String

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        signal: String? = nil,
        exceptionName: String? = nil,
        exceptionReason: String? = nil,
        callStack: [String] = [],
        breadcrumbs: [String] = [],
        activeModel: String? = nil,
        activeExecutionMode: String? = nil,
        activeThreadID: String? = nil,
        memoryUsageBytes: UInt64 = 0,
        osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
        appVersion: String = "1.0.0",
        architecture: String = {
            #if arch(arm64)
            return "arm64"
            #elseif arch(x86_64)
            return "x86_64"
            #else
            return "unknown"
            #endif
        }()
    ) {
        self.id = id
        self.timestamp = timestamp
        self.signal = signal
        self.exceptionName = exceptionName
        self.exceptionReason = exceptionReason
        self.callStack = callStack
        self.breadcrumbs = breadcrumbs
        self.activeModel = activeModel
        self.activeExecutionMode = activeExecutionMode
        self.activeThreadID = activeThreadID
        self.memoryUsageBytes = memoryUsageBytes
        self.osVersion = osVersion
        self.appVersion = appVersion
        self.architecture = architecture
    }

    /// Formats the crash report as a clean diagnostic text block suitable for copying or submitting.
    public var formattedSummary: String {
        let formatter = ISO8601DateFormatter()
        var text = """
        ================================================================================
        💥 ADVENTURERS HARNESS CRASH REPORT
        ================================================================================
        Report ID:     \(id)
        Timestamp:     \(formatter.string(from: timestamp))
        App Version:   \(appVersion) (\(architecture))
        OS Version:    \(osVersion)
        Active Model:  \(activeModel ?? "None")
        Active Mode:   \(activeExecutionMode ?? "None")
        Active Thread: \(activeThreadID ?? "None")
        Memory RSS:    \(ByteCountFormatter.string(fromByteCount: Int64(memoryUsageBytes), countStyle: .memory))

        """

        if let sig = signal {
            text += "\nSignal:        \(sig)\n"
        }
        if let name = exceptionName {
            text += "Exception:     \(name)\n"
        }
        if let reason = exceptionReason {
            text += "Reason:        \(reason)\n"
        }

        if !breadcrumbs.isEmpty {
            text += "\n--- Recent Activity Breadcrumbs (Last \(breadcrumbs.count)) ---\n"
            for (idx, b) in breadcrumbs.enumerated() {
                text += "[\(idx + 1)] \(b)\n"
            }
        }

        if !callStack.isEmpty {
            text += "\n--- Thread Call Stack Backtrace ---\n"
            for frame in callStack {
                text += "\(frame)\n"
            }
        }

        text += "\n================================================================================\n"
        return text
    }
}

// MARK: - Crash Reporter Manager

public final class CrashReporterManager: @unchecked Sendable {
    public static let shared = CrashReporterManager()

    private let lock = OSAllocatedUnfairLock()
    private var _breadcrumbs: [String] = []
    private let maxBreadcrumbs = 40

    public var activeModel: String?
    public var activeExecutionMode: String?
    public var activeThreadID: String?

    public var crashDirectory: URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".adventurers", isDirectory: true)
            .appendingPathComponent("crashes", isDirectory: true)
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    public init() {
        installUncaughtExceptionHandler()
    }

    // MARK: - Breadcrumb Tracking

    public func addBreadcrumb(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "[\(timestamp)] \(message)"
        lock.withLock {
            _breadcrumbs.append(entry)
            if _breadcrumbs.count > maxBreadcrumbs {
                _breadcrumbs.removeFirst(_breadcrumbs.count - maxBreadcrumbs)
            }
        }
    }

    public var recentBreadcrumbs: [String] {
        lock.withLock { _breadcrumbs }
    }

    // MARK: - Handler Installation

    public func installUncaughtExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let symbols = exception.callStackSymbols
            let name = exception.name.rawValue
            let reason = exception.reason ?? "Unknown NSException"
            
            CrashReporterManager.shared.recordCrash(
                signal: nil,
                exceptionName: name,
                exceptionReason: reason,
                callStack: symbols
            )
        }

        // Install signal traps
        let signals = [SIGSEGV, SIGBUS, SIGABRT, SIGILL, SIGFPE, SIGTRAP]
        for sig in signals {
            var action = sigaction()
            action.__sigaction_u.__sa_handler = { signum in
                let symbols = Thread.callStackSymbols
                let sigName: String
                switch signum {
                case SIGSEGV: sigName = "SIGSEGV (Segmentation Fault)"
                case SIGBUS:  sigName = "SIGBUS (Bus Error)"
                case SIGABRT: sigName = "SIGABRT (Abort Process)"
                case SIGILL:  sigName = "SIGILL (Illegal Instruction)"
                case SIGFPE:  sigName = "SIGFPE (Floating Point Error)"
                case SIGTRAP: sigName = "SIGTRAP (Trace/Breakpoint Trap)"
                default:      sigName = "Signal \(signum)"
                }

                CrashReporterManager.shared.recordCrash(
                    signal: sigName,
                    exceptionName: nil,
                    exceptionReason: "Fatal Unix Signal",
                    callStack: symbols
                )

                // Restore default handler and re-raise
                signal(signum, SIG_DFL)
                raise(signum)
            }
            sigaction(sig, &action, nil)
        }
    }

    // MARK: - Crash Recording & Persistence

    @discardableResult
    public func recordCrash(
        signal: String?,
        exceptionName: String?,
        exceptionReason: String?,
        callStack: [String]
    ) -> CrashReport {
        var rusage = rusage()
        getrusage(RUSAGE_SELF, &rusage)
        let memoryBytes = UInt64(rusage.ru_maxrss)

        let report = CrashReport(
            signal: signal,
            exceptionName: exceptionName,
            exceptionReason: exceptionReason,
            callStack: callStack,
            breadcrumbs: recentBreadcrumbs,
            activeModel: activeModel,
            activeExecutionMode: activeExecutionMode,
            activeThreadID: activeThreadID,
            memoryUsageBytes: memoryBytes
        )

        saveCrashReport(report)
        return report
    }

    public func saveCrashReport(_ report: CrashReport) {
        let dir = crashDirectory
        let filename = "crash_\(Int(report.timestamp.timeIntervalSince1970))_\(report.id.prefix(8))"
        let jsonURL = dir.appendingPathComponent("\(filename).json")
        let logURL = dir.appendingPathComponent("\(filename).log")

        // Save JSON representation
        if let data = try? JSONEncoder().encode(report) {
            try? data.write(to: jsonURL)
        }

        // Save human-readable summary
        if let logData = report.formattedSummary.data(using: .utf8) {
            try? logData.write(to: logURL)
        }
    }

    // MARK: - Query & Diagnostics

    public func listCrashReports() -> [CrashReport] {
        let dir = crashDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }

        let jsonFiles = files.filter { $0.pathExtension == "json" }
        var reports: [CrashReport] = []

        for file in jsonFiles {
            if let data = try? Data(contentsOf: file),
               let report = try? JSONDecoder().decode(CrashReport.self, from: data) {
                reports.append(report)
            }
        }

        return reports.sorted { $0.timestamp > $1.timestamp }
    }

    public func readLatestCrashReport() -> CrashReport? {
        return listCrashReports().first
    }

    public func clearAllCrashReports() {
        let dir = crashDirectory
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// Scans macOS system diagnostic reports directory (`~/Library/Logs/DiagnosticReports/`) for Adventurers crashes.
    public func findSystemDiagnosticReports() -> [URL] {
        let systemDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: systemDir, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }

        return files.filter { $0.lastPathComponent.hasPrefix("Adventurers") }
            .sorted { (u1, u2) -> Bool in
                let d1 = (try? u1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let d2 = (try? u2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return d1 > d2
            }
    }
}
