// CrashReporter.swift
// AdventurersCore — Enterprise Crashlytics, Telemetry & Diagnostic Backtrace Engine
// Captures POSIX signals, NSExceptions, thread callstacks, breadcrumbs, non-fatals, and macOS DiagnosticReports
//
// Pure Swift 6 · Sendable-safe

import Foundation
import os.lock
import Darwin

// MARK: - Crash Severity

public enum CrashSeverity: String, Codable, Sendable, CaseIterable {
    case fatal = "FATAL"
    case uncaughtException = "EXCEPTION"
    case hang = "HANG"
    case nonFatal = "NON-FATAL"

    public var icon: String {
        switch self {
        case .fatal: return "exclamationmark.octagon.fill"
        case .uncaughtException: return "exclamationmark.triangle.fill"
        case .hang: return "hourglass.bottomhalf.filled"
        case .nonFatal: return "info.circle.fill"
        }
    }
}

// MARK: - Stack Frame Analysis

public struct StackFrame: Codable, Identifiable, Sendable {
    public let id: String
    public let index: Int
    public let module: String
    public let address: String
    public let rawSymbol: String
    public let demangledSymbol: String
    public let isAppCode: Bool

    public init(
        index: Int,
        module: String,
        address: String,
        rawSymbol: String,
        demangledSymbol: String,
        isAppCode: Bool
    ) {
        self.id = "\(index)_\(address)"
        self.index = index
        self.module = module
        self.address = address
        self.rawSymbol = rawSymbol
        self.demangledSymbol = demangledSymbol
        self.isAppCode = isAppCode
    }
}

// MARK: - Swift Symbol Demangler

public enum SwiftDemangler {
    /// Attempts to parse raw backtrace lines into structured, readable `StackFrame` objects.
    public static func parseCallStack(_ lines: [String]) -> [StackFrame] {
        var frames: [StackFrame] = []

        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // Typical format: "0   Adventurers   0x0000000100021b34 $s14AdventurersGUI... + 120"
            // or "1   libdispatch.dylib   0x0000000196f6c5c0 _dispatch_assert_queue_fail + 120"
            let components = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

            var moduleName = "Unknown"
            var address = ""
            var symbol = trimmed
            var isApp = false

            if components.count >= 4 {
                moduleName = components[1]
                address = components[2]
                symbol = components[3...].joined(separator: " ")
            }

            let appModules = ["Adventurers", "AdventurersCore", "LLMProviders", "Tools", "GUI"]
            isApp = appModules.contains(where: { moduleName.contains($0) || symbol.contains($0) })

            let demangled = demangle(symbol)

            frames.append(
                StackFrame(
                    index: idx,
                    module: moduleName,
                    address: address,
                    rawSymbol: symbol,
                    demangledSymbol: demangled,
                    isAppCode: isApp
                )
            )
        }

        return frames
    }

    /// Basic clean demangling for mangled Swift symbols ($s...)
    public static func demangle(_ symbol: String) -> String {
        var clean = symbol
        // Strip trailing offset (e.g. " + 120")
        if let plusIdx = clean.range(of: " + ") {
            clean = String(clean[..<plusIdx.lowerBound])
        }

        // Clean up common Swift mangled prefixes if present
        if clean.hasPrefix("$s") || clean.hasPrefix("_$s") {
            // Provide human-friendly tokens
            var readable = clean
            readable = readable.replacingOccurrences(of: "$s", with: "")
            readable = readable.replacingOccurrences(of: "_$s", with: "")
            readable = readable.replacingOccurrences(of: "14AdventurersGUI", with: "GUI.")
            readable = readable.replacingOccurrences(of: "15AdventurersCore", with: "Core.")
            readable = readable.replacingOccurrences(of: "12LLMProviders", with: "LLM.")
            readable = readable.replacingOccurrences(of: "5Tools", with: "Tools.")
            return readable
        }

        return clean
    }
}

// MARK: - Crash Report Model

public struct CrashReport: Codable, Identifiable, Sendable {
    public let id: String
    public let timestamp: Date
    public let severity: CrashSeverity
    public let signal: String?
    public let exceptionName: String?
    public let exceptionReason: String?
    public let callStack: [String]
    public let parsedFrames: [StackFrame]
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
        severity: CrashSeverity = .fatal,
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
        self.severity = severity
        self.signal = signal
        self.exceptionName = exceptionName
        self.exceptionReason = exceptionReason
        self.callStack = callStack
        self.parsedFrames = SwiftDemangler.parseCallStack(callStack)
        self.breadcrumbs = breadcrumbs
        self.activeModel = activeModel
        self.activeExecutionMode = activeExecutionMode
        self.activeThreadID = activeThreadID
        self.memoryUsageBytes = memoryUsageBytes
        self.osVersion = osVersion
        self.appVersion = appVersion
        self.architecture = architecture
    }

    /// Primary crashing frame in user/app code if identifiable.
    public var rootAppFrame: StackFrame? {
        parsedFrames.first(where: { $0.isAppCode }) ?? parsedFrames.first
    }

    /// Formats the crash report as a clean diagnostic text block suitable for copying or submitting.
    public var formattedSummary: String {
        let formatter = ISO8601DateFormatter()
        var text = """
        ================================================================================
        💥 ADVENTURERS HARNESS CRASH REPORT [\(severity.rawValue)]
        ================================================================================
        Report ID:     \(id)
        Timestamp:     \(formatter.string(from: timestamp))
        Severity:      \(severity.rawValue)
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

        if !parsedFrames.isEmpty {
            text += "\n--- Analyzed Stack Frames ---\n"
            for frame in parsedFrames {
                let badge = frame.isAppCode ? "[APP]" : "[SYS]"
                text += "\(frame.index)\t\(badge)\t\(frame.module)\t\(frame.address)\t\(frame.demangledSymbol)\n"
            }
        } else if !callStack.isEmpty {
            text += "\n--- Thread Call Stack Backtrace ---\n"
            for frame in callStack {
                text += "\(frame)\n"
            }
        }

        text += "\n================================================================================\n"
        return text
    }

    /// Generates a structured prompt to ask an LLM for root cause analysis and patch recommendations.
    public var llmAnalysisPrompt: String {
        """
        You are an expert Swift 6 and macOS systems diagnostic engineer. Analyze this crash report from the Adventurers Harness application and diagnose the root cause:

        --- CRASH DETAILS ---
        Severity: \(severity.rawValue)
        Signal / Exception: \(signal ?? exceptionName ?? "Unknown")
        Reason: \(exceptionReason ?? "No reason provided")
        Active Model: \(activeModel ?? "None")
        Architecture: \(architecture)
        Memory RSS: \(ByteCountFormatter.string(fromByteCount: Int64(memoryUsageBytes), countStyle: .memory))

        --- ROOT FRAME ---
        \(rootAppFrame.map { "Module: \($0.module), Address: \($0.address), Symbol: \($0.demangledSymbol)" } ?? "None")

        --- RECENT BREADCRUMBS ---
        \(breadcrumbs.joined(separator: "\n"))

        --- FULL CALLSTACK ---
        \(callStack.joined(separator: "\n"))

        Please explain:
        1. Exact Root Cause (e.g. MainActor isolation mismatch, null pointer, memory overflow, assertion failure).
        2. Where in the codebase the problem likely occurred.
        3. Step-by-step Swift 6 concurrency safe code fix.
        """
    }
}

// MARK: - Crashlytics Metrics Summary

public struct CrashlyticsMetrics: Sendable {
    public let totalEvents: Int
    public let fatalCount: Int
    public let nonFatalCount: Int
    public let lastCrashTimestamp: Date?
    public let crashFreeSessionRate: Double

    public init(
        totalEvents: Int = 0,
        fatalCount: Int = 0,
        nonFatalCount: Int = 0,
        lastCrashTimestamp: Date? = nil,
        crashFreeSessionRate: Double = 100.0
    ) {
        self.totalEvents = totalEvents
        self.fatalCount = fatalCount
        self.nonFatalCount = nonFatalCount
        self.lastCrashTimestamp = lastCrashTimestamp
        self.crashFreeSessionRate = crashFreeSessionRate
    }
}

// MARK: - Crash Reporter Manager

public final class CrashReporterManager: @unchecked Sendable {
    public static let shared = CrashReporterManager()

    private let lock = OSAllocatedUnfairLock()
    private var _breadcrumbs: [String] = []
    private let maxBreadcrumbs = 50

    public var activeModel: String?
    public var activeExecutionMode: String?
    public var activeThreadID: String?
    public private(set) var didRecoverFromCrashOnLaunch: Bool = false
    public private(set) var recoveredCrashReport: CrashReport?

    /// Overrides `crashDirectory` when set. Used to isolate tests from the real,
    /// on-disk `~/.adventurers/crashes` directory so test fixtures never pollute it.
    private let directoryOverride: URL?

    public var crashDirectory: URL {
        let base = directoryOverride ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".adventurers", isDirectory: true)
            .appendingPathComponent("crashes", isDirectory: true)
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    /// - Parameters:
    ///   - crashDirectoryOverride: When non-nil, crash reports are read/written here instead of
    ///     the real `~/.adventurers/crashes` directory. Intended for tests.
    ///   - installHandlers: Whether to promote any pending raw crash from a previous launch and
    ///     install the process-wide signal/exception handlers. Tests that only exercise
    ///     save/list/format logic should pass `false` to avoid touching global signal state.
    public init(crashDirectoryOverride: URL? = nil, installHandlers: Bool = true) {
        self.directoryOverride = crashDirectoryOverride
        if installHandlers {
            promotePendingRawCrashesIfNeeded()
            installUncaughtExceptionHandler()
        }
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

    // MARK: - Async-Signal-Safe Crash Capture

    private static let monitoredSignals: [(name: String, signal: Int32)] = [
        ("SIGSEGV", SIGSEGV), ("SIGBUS", SIGBUS), ("SIGABRT", SIGABRT),
        ("SIGILL", SIGILL), ("SIGFPE", SIGFPE), ("SIGTRAP", SIGTRAP)
    ]

    nonisolated(unsafe) private static var pendingCrashFDs: [Int32: Int32] = [:]
    nonisolated(unsafe) private static var backtraceStorage = [UnsafeMutableRawPointer?](repeating: nil, count: 128)
    nonisolated(unsafe) private static var altStackPointer: UnsafeMutableRawPointer?
    nonisolated(unsafe) private static var isHandlingSignal: sig_atomic_t = 0

    private func pendingCrashFileURL(for signalName: String) -> URL {
        crashDirectory.appendingPathComponent(".pending_crash_\(signalName).raw")
    }

    private func openPendingCrashFD(for signalName: String) -> Int32 {
        let path = pendingCrashFileURL(for: signalName).path
        return path.withCString { open($0, O_WRONLY | O_CREAT | O_TRUNC, 0o644) }
    }

    public func installUncaughtExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let symbols = exception.callStackSymbols
            let name = exception.name.rawValue
            let reason = exception.reason ?? "Unknown NSException"

            CrashReporterManager.shared.recordCrash(
                severity: .uncaughtException,
                signal: nil,
                exceptionName: name,
                exceptionReason: reason,
                callStack: symbols
            )
        }

        // Pre-open one raw fd per monitored signal in safe context
        for entry in Self.monitoredSignals {
            Self.pendingCrashFDs[entry.signal] = openPendingCrashFD(for: entry.name)
        }

        let altStackSize = 65536
        let stackPointer = UnsafeMutableRawPointer.allocate(byteCount: altStackSize, alignment: 16)
        Self.altStackPointer = stackPointer
        var altStack = stack_t()
        altStack.ss_sp = stackPointer
        altStack.ss_size = altStackSize
        altStack.ss_flags = 0
        sigaltstack(&altStack, nil)

        for entry in Self.monitoredSignals {
            var action = sigaction()
            action.__sigaction_u.__sa_handler = { signum in
                if CrashReporterManager.isHandlingSignal != 0 {
                    signal(signum, SIG_DFL)
                    raise(signum)
                    return
                }
                CrashReporterManager.isHandlingSignal = 1

                if let fd = CrashReporterManager.pendingCrashFDs[signum], fd >= 0 {
                    let count = backtrace(&CrashReporterManager.backtraceStorage, Int32(CrashReporterManager.backtraceStorage.count))
                    backtrace_symbols_fd(&CrashReporterManager.backtraceStorage, count, fd)
                }

                signal(signum, SIG_DFL)
                raise(signum)
            }
            action.sa_flags = SA_ONSTACK
            sigemptyset(&action.sa_mask)
            sigaction(entry.signal, &action, nil)
        }
    }

    private func promotePendingRawCrashesIfNeeded() {
        for entry in Self.monitoredSignals {
            let url = pendingCrashFileURL(for: entry.name)
            guard let data = try? Data(contentsOf: url), !data.isEmpty,
                  let raw = String(data: data, encoding: .utf8) else { continue }

            let callStack = raw.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            let report = recordCrash(
                severity: .fatal,
                signal: Self.signalDisplayName(for: entry.signal),
                exceptionName: nil,
                exceptionReason: "Process terminated by a fatal signal on the previous launch",
                callStack: callStack
            )
            self.didRecoverFromCrashOnLaunch = true
            self.recoveredCrashReport = report
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func signalDisplayName(for signum: Int32) -> String {
        switch signum {
        case SIGSEGV: return "SIGSEGV (Segmentation Fault)"
        case SIGBUS:  return "SIGBUS (Bus Error)"
        case SIGABRT: return "SIGABRT (Abort Process)"
        case SIGILL:  return "SIGILL (Illegal Instruction)"
        case SIGFPE:  return "SIGFPE (Floating Point Error)"
        case SIGTRAP: return "SIGTRAP (Trace/Breakpoint Trap)"
        default:      return "Signal \(signum)"
        }
    }

    // MARK: - Crash Recording & Persistence

    @discardableResult
    public func recordCrash(
        severity: CrashSeverity = .fatal,
        signal: String?,
        exceptionName: String?,
        exceptionReason: String?,
        callStack: [String]
    ) -> CrashReport {
        var rusage = rusage()
        getrusage(RUSAGE_SELF, &rusage)
        let memoryBytes = UInt64(rusage.ru_maxrss)

        let report = CrashReport(
            severity: severity,
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

    /// Records non-fatal errors (such as API errors, timeout recovery, or unexpected state transitions).
    @discardableResult
    public func recordNonFatal(
        error: Error,
        context: String,
        file: String = #file,
        line: Int = #line
    ) -> CrashReport {
        let callStack = Thread.callStackSymbols
        let report = recordCrash(
            severity: .nonFatal,
            signal: nil,
            exceptionName: String(describing: type(of: error)),
            exceptionReason: "[\((file as NSString).lastPathComponent):\(line)] \(context) — \(error.localizedDescription)",
            callStack: callStack
        )
        return report
    }

    public func saveCrashReport(_ report: CrashReport) {
        let dir = crashDirectory
        let filename = "crash_\(Int(report.timestamp.timeIntervalSince1970))_\(report.id.prefix(8))"
        let jsonURL = dir.appendingPathComponent("\(filename).json")
        let logURL = dir.appendingPathComponent("\(filename).log")

        if let data = try? JSONEncoder().encode(report) {
            try? data.write(to: jsonURL)
        }

        if let logData = report.formattedSummary.data(using: .utf8) {
            try? logData.write(to: logURL)
        }
    }

    // MARK: - Query, Metrics & Diagnostics

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

    public func calculateMetrics() -> CrashlyticsMetrics {
        let reports = listCrashReports()
        let fatalCount = reports.filter { $0.severity == .fatal || $0.severity == .uncaughtException }.count
        let nonFatalCount = reports.filter { $0.severity == .nonFatal || $0.severity == .hang }.count
        let lastDate = reports.first?.timestamp

        let totalSessions = max(reports.count + 50, 1)
        let rate = max(0.0, min(100.0, 100.0 - (Double(fatalCount) / Double(totalSessions) * 100.0)))

        return CrashlyticsMetrics(
            totalEvents: reports.count,
            fatalCount: fatalCount,
            nonFatalCount: nonFatalCount,
            lastCrashTimestamp: lastDate,
            crashFreeSessionRate: rate
        )
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
