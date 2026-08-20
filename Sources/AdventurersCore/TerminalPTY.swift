// TerminalPTY.swift
// AdventurersCore — POSIX Pseudo-Terminal (PTY) Subsystem for macOS Apple Silicon
// Implements openpty/forkpty Darwin system calls, TIOCSWINSZ window resize, and bidirectional non-blocking streams.

import Foundation
import Darwin

// MARK: - PTY Window Size

public struct TerminalWindowSize: Sendable, Equatable {
    public var cols: UInt16
    public var rows: UInt16

    public init(cols: UInt16 = 80, rows: UInt16 = 24) {
        self.cols = cols
        self.rows = rows
    }
}

// MARK: - PTY Errors

public enum TerminalPTYError: Error, LocalizedError, Sendable {
    case openPTYFailed(errno: Int32)
    case grantPTFailed(errno: Int32)
    case unlockPTFailed(errno: Int32)
    case setWindowSizeFailed(errno: Int32)
    case spawnProcessFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openPTYFailed(let err): return "openpty failed with errno: \(err)"
        case .grantPTFailed(let err): return "grantpt failed with errno: \(err)"
        case .unlockPTFailed(let err): return "unlockpt failed with errno: \(err)"
        case .setWindowSizeFailed(let err): return "TIOCSWINSZ window resize failed with errno: \(err)"
        case .spawnProcessFailed(let msg): return "PTY process spawn failed: \(msg)"
        }
    }
}

// MARK: - POSIX PTY Session Manager

public final class TerminalPTY: @unchecked Sendable {
    public private(set) var masterFD: Int32 = -1
    public private(set) var slaveFD: Int32 = -1
    public private(set) var childPID: pid_t = -1
    public private(set) var windowSize: TerminalWindowSize

    private var readSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.bytecats.adventurers.pty.queue", qos: .userInteractive)
    private var isClosed: Bool = false
    private let lock = NSLock()

    public var onOutputReceived: (@Sendable (Data) -> Void)?
    public var onProcessTerminated: (@Sendable (Int32) -> Void)?

    public init(windowSize: TerminalWindowSize = TerminalWindowSize()) throws {
        self.windowSize = windowSize
        try allocatePTY()
    }

    deinit {
        closePTY()
    }

    // MARK: - Allocation & Setup

    private func allocatePTY() throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        var win = winsize(
            ws_row: windowSize.rows,
            ws_col: windowSize.cols,
            ws_xpixel: 0,
            ws_ypixel: 0
        )

        let result = openpty(&master, &slave, nil, nil, &win)
        guard result == 0 else {
            throw TerminalPTYError.openPTYFailed(errno: errno)
        }

        self.masterFD = master
        self.slaveFD = slave

        // Set non-blocking on master
        let flags = fcntl(master, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(master, F_SETFL, flags | O_NONBLOCK)
        }
    }

    // MARK: - Resize Window (TIOCSWINSZ)

    public func resize(cols: UInt16, rows: UInt16) throws {
        lock.lock()
        defer { lock.unlock() }
        guard masterFD >= 0 else { return }

        self.windowSize = TerminalWindowSize(cols: cols, rows: rows)
        var win = winsize(
            ws_row: rows,
            ws_col: cols,
            ws_xpixel: 0,
            ws_ypixel: 0
        )

        let result = ioctl(masterFD, TIOCSWINSZ, &win)
        guard result == 0 else {
            throw TerminalPTYError.setWindowSizeFailed(errno: errno)
        }
    }

    // MARK: - Process Spawning

    public func spawn(
        executable: String = "/bin/zsh",
        arguments: [String] = ["-l"],
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        environment: [String: String]? = nil
    ) throws {
        guard masterFD >= 0 && slaveFD >= 0 else {
            throw TerminalPTYError.spawnProcessFailed("PTY file descriptors not allocated")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        var env = environment ?? ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
        process.environment = env

        let slaveHandle = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: false)
        process.standardInput = slaveHandle
        process.standardOutput = slaveHandle
        process.standardError = slaveHandle

        do {
            try process.run()
            self.childPID = process.processIdentifier
            startReadingMaster()

            // Monitor process exit on background queue
            Task.detached(priority: .background) { [weak self] in
                process.waitUntilExit()
                let status = process.terminationStatus
                self?.onProcessTerminated?(status)
                self?.closePTY()
            }
        } catch {
            throw TerminalPTYError.spawnProcessFailed(error.localizedDescription)
        }
    }

    // MARK: - Stream Reading & Writing

    private func startReadingMaster() {
        guard masterFD >= 0 else { return }

        let source = DispatchSource.makeReadSource(fileDescriptor: masterFD, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = read(self.masterFD, &buffer, buffer.count)
            if bytesRead > 0 {
                let data = Data(buffer.prefix(bytesRead))
                self.onOutputReceived?(data)
            } else if bytesRead == 0 {
                // EOF
                source.cancel()
            }
        }
        source.setCancelHandler { [weak self] in
            self?.closeMaster()
        }
        self.readSource = source
        source.resume()
    }

    public func writeInput(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        writeInput(data)
    }

    public func writeInput(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard masterFD >= 0 else { return }

        data.withUnsafeBytes { raw in
            guard let ptr = raw.baseAddress else { return }
            _ = write(masterFD, ptr, data.count)
        }
    }

    // MARK: - Teardown

    private func closeMaster() {
        if masterFD >= 0 {
            close(masterFD)
            masterFD = -1
        }
    }

    private func closeSlave() {
        if slaveFD >= 0 {
            close(slaveFD)
            slaveFD = -1
        }
    }

    public func closePTY() {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return }
        isClosed = true

        if let source = readSource {
            source.cancel()
            readSource = nil
        } else {
            closeMaster()
        }
        closeSlave()

        if childPID > 0 {
            kill(childPID, SIGTERM)
            childPID = -1
        }
    }
}
