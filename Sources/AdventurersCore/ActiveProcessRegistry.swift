// AdventurersCore - ActiveProcessRegistry
// Tracks, monitors, and terminates active terminal commands, subprocesses, and child process trees

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Thread-safe registry for actively executing subprocesses (bash commands, meta-harnesses, tools).
public final class ActiveProcessRegistry: @unchecked Sendable {
    public static let shared = ActiveProcessRegistry()

    private let lock = NSLock()
    private var processes: [Int32: Process] = [:]
    private var threadProcessMap: [UUID: Set<Int32>] = [:]

    private init() {}

    /// Registers a running process for monitoring and lifecycle control.
    public func register(process: Process, threadID: UUID? = nil) {
        lock.lock()
        defer { lock.unlock() }

        let pid = process.processIdentifier
        guard pid > 0 else { return }

        processes[pid] = process
        if let tid = threadID {
            threadProcessMap[tid, default: []].insert(pid)
        }
    }

    /// Unregisters a process after normal completion.
    public func unregister(process: Process, threadID: UUID? = nil) {
        lock.lock()
        defer { lock.unlock() }

        let pid = process.processIdentifier
        processes.removeValue(forKey: pid)
        if let tid = threadID {
            threadProcessMap[tid]?.remove(pid)
        }
    }

    /// Unregisters a process by PID.
    public func unregister(pid: Int32) {
        lock.lock()
        defer { lock.unlock() }

        processes.removeValue(forKey: pid)
        for (tid, var set) in threadProcessMap {
            if set.contains(pid) {
                set.remove(pid)
                threadProcessMap[tid] = set
            }
        }
    }

    /// Forcefully kills a specific process and its entire child process tree (e.g. \`find\`, \`grep\`, \`swift\`).
    public func killProcess(_ process: Process) {
        let pid = process.processIdentifier
        guard pid > 0 else {
            process.terminate()
            return
        }
        killProcessTree(pid: pid, process: process)
        unregister(pid: pid)
    }

    /// Forcefully kills all active subprocesses associated with a specific thread.
    public func killProcesses(for threadID: UUID) {
        lock.lock()
        let pids = threadProcessMap[threadID] ?? []
        let procsToKill = pids.compactMap { processes[$0] }
        threadProcessMap.removeValue(forKey: threadID)
        for pid in pids {
            processes.removeValue(forKey: pid)
        }
        lock.unlock()

        for proc in procsToKill {
            killProcessTree(pid: proc.processIdentifier, process: proc)
        }
    }

    /// Forcefully kills ALL active subprocesses globally across all threads.
    public func killAllProcesses() {
        lock.lock()
        let procsToKill = Array(processes.values)
        processes.removeAll()
        threadProcessMap.removeAll()
        lock.unlock()

        for proc in procsToKill {
            killProcessTree(pid: proc.processIdentifier, process: proc)
        }
    }

    /// Internal tree kill sending SIGTERM/SIGKILL to process group, child processes, and process itself.
    private func killProcessTree(pid: Int32, process: Process?) {
        guard pid > 0 else { return }

        // 1. Kill any child processes spawned by this PID (e.g. find, grep, swift, cargo)
        #if os(macOS) || os(Linux)
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-9", "-P", "\(pid)"]
        try? pkill.run()
        pkill.waitUntilExit()
        #endif

        // 2. Kill the process group if leader
        #if canImport(Darwin) || canImport(Glibc)
        kill(-pid, SIGTERM)
        kill(pid, SIGTERM)
        kill(-pid, SIGKILL)
        kill(pid, SIGKILL)
        #endif

        // 3. Fallback Foundation terminate
        process?.terminate()
    }
}
