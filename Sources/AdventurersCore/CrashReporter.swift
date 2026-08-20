// CrashReporter.swift
// AdventurersCore — Native Crash Diagnostic & Backtrace Reporting Engine
// Captures POSIX signals, NSExceptions, thread callstacks, breadcrumbs, and macOS DiagnosticReports
//
// Pure Swift 6 · Sendable-safe

import Foundation
import os.lock
import Darwin

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
    //
    // A POSIX signal handler must not call malloc, take locks, or touch the Swift/ObjC runtime —
    // if the crashing thread already held the allocator's internal lock (a common case for
    // SIGABRT/SIGSEGV), doing so self-deadlocks the process instead of producing a report, and the
    // "crash" just silently hangs or gets killed with nothing on disk. The previous implementation
    // called straight into JSONEncoder/FileManager/String interpolation from inside the handler.
    //
    // Instead, the handler here only touches two primitives that don't allocate:
    //   - `backtrace()` into a preallocated static buffer (no malloc).
    //   - `backtrace_symbols_fd()`, which per its man page "does not call malloc(3)" and writes
    //     directly to a file descriptor that was opened ahead of time, outside signal context.
    // Each monitored signal gets its own pre-opened fd so the handler never needs to format a
    // filename. The resulting raw dump is picked up and turned into a full `CrashReport` the next
    // time the app launches, via `promotePendingRawCrashesIfNeeded()`.

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

            // NSSetUncaughtExceptionHandler runs in normal application context (invoked by the
            // ObjC runtime before it terminates the process), not inside an async signal handler,
            // so it's safe to use Foundation/JSON here.
            CrashReporterManager.shared.recordCrash(
                signal: nil,
                exceptionName: name,
                exceptionReason: reason,
                callStack: symbols
            )
        }

        // Pre-open one raw fd per monitored signal, in this safe (non-signal) context.
        for entry in Self.monitoredSignals {
            Self.pendingCrashFDs[entry.signal] = openPendingCrashFD(for: entry.name)
        }

        // Dedicated alternate signal stack so a stack-overflow SIGSEGV can still be handled
        // (the thread's normal stack is unusable at that point).
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
                // Guard re-entrancy: a crash while already handling a crash just falls through
                // to the default handler instead of looping or double-writing.
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

                // Restore default handler and re-raise so the OS's own crash reporting
                // (and debuggers) still see the fatal signal.
                signal(signum, SIG_DFL)
                raise(signum)
            }
            action.sa_flags = SA_ONSTACK
            sigemptyset(&action.sa_mask)
            sigaction(entry.signal, &action, nil)
        }
    }

    /// Reads any raw crash dump left behind by a fatal signal on a previous run, converts it into
    /// a full `CrashReport`, and clears the raw file. Safe to call from normal (non-signal) context.
    private func promotePendingRawCrashesIfNeeded() {
        for entry in Self.monitoredSignals {
            let url = pendingCrashFileURL(for: entry.name)
            guard let data = try? Data(contentsOf: url), !data.isEmpty,
                  let raw = String(data: data, encoding: .utf8) else { continue }

            let callStack = raw.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            recordCrash(
                signal: Self.signalDisplayName(for: entry.signal),
                exceptionName: nil,
                exceptionReason: "Process terminated by a fatal signal on the previous launch",
                callStack: callStack
            )
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
