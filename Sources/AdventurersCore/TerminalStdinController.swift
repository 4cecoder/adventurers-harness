// TerminalStdinController.swift
// AdventurersCore — Bi-Directional Interactive Stdin Controller for POSIX PTY
// Handles ANSI/VT100 keycodes, control characters (Ctrl+C, Ctrl+D, Ctrl+Z), and interactive command dispatch.

import Foundation

public enum TerminalKey: Sendable, Equatable {
    case character(Character)
    case enter
    case tab
    case backspace
    case delete
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
    case home
    case end
    case pageUp
    case pageDown
    case escape
    case ctrl(Character)

    /// Converts the key into standard VT100/xterm byte sequence
    public var bytes: [UInt8] {
        switch self {
        case .character(let char):
            return Array(String(char).utf8)
        case .enter:
            return [0x0D] // \r
        case .tab:
            return [0x09] // \t
        case .backspace:
            return [0x7F] // DEL / Backspace
        case .delete:
            return [0x1B, 0x5B, 0x33, 0x7E] // \x1b[3~
        case .arrowUp:
            return [0x1B, 0x5B, 0x41] // \x1b[A
        case .arrowDown:
            return [0x1B, 0x5B, 0x42] // \x1b[B
        case .arrowRight:
            return [0x1B, 0x5B, 0x43] // \x1b[C
        case .arrowLeft:
            return [0x1B, 0x5B, 0x44] // \x1b[D
        case .home:
            return [0x1B, 0x5B, 0x48] // \x1b[H
        case .end:
            return [0x1B, 0x5B, 0x46] // \x1b[F
        case .pageUp:
            return [0x1B, 0x5B, 0x35, 0x7E] // \x1b[5~
        case .pageDown:
            return [0x1B, 0x5B, 0x36, 0x7E] // \x1b[6~
        case .escape:
            return [0x1B]
        case .ctrl(let char):
            let upper = String(char).uppercased().first ?? "C"
            if let ascii = upper.asciiValue, ascii >= 65 && ascii <= 90 {
                return [ascii - 64] // A=1 (Ctrl+A), C=3 (Ctrl+C), D=4 (Ctrl+D), Z=26 (Ctrl+Z)
            }
            return [0x03]
        }
    }

    public var data: Data {
        Data(bytes)
    }
}

public final class TerminalStdinController: @unchecked Sendable {
    public weak var pty: TerminalPTY?
    private var history: [String] = []
    private var historyIndex: Int = 0
    private let lock = NSLock()

    public init(pty: TerminalPTY? = nil) {
        self.pty = pty
    }

    public func attach(pty: TerminalPTY) {
        lock.lock()
        defer { lock.unlock() }
        self.pty = pty
    }

    /// Sends a high-level key event to the PTY
    public func sendKey(_ key: TerminalKey) {
        guard let pty = pty else { return }
        pty.writeInput(key.data)
    }

    /// Sends a raw text string to the PTY
    public func sendText(_ text: String) {
        guard let pty = pty else { return }
        pty.writeInput(text)
    }

    /// Sends a line executed by Enter (and records to history)
    public func sendLine(_ line: String) {
        lock.lock()
        if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            history.append(line)
            historyIndex = history.count
        }
        lock.unlock()

        sendText(line + "\n")
    }

    /// Interrupt signal (SIGINT / Ctrl+C)
    public func sendInterrupt() {
        sendKey(.ctrl("c"))
    }

    /// End of Transmission / EOF (Ctrl+D)
    public func sendEOF() {
        sendKey(.ctrl("d"))
    }

    /// Suspend signal (SIGTSTP / Ctrl+Z)
    public func sendSuspend() {
        sendKey(.ctrl("z"))
    }

    /// Clear Screen (Ctrl+L)
    public func sendClear() {
        sendKey(.ctrl("l"))
    }

    /// Navigate back in command history
    public func historyPrevious() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard !history.isEmpty else { return nil }
        if historyIndex > 0 {
            historyIndex -= 1
        }
        return history[historyIndex]
    }

    /// Navigate forward in command history
    public func historyNext() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard !history.isEmpty else { return nil }
        if historyIndex < history.count - 1 {
            historyIndex += 1
            return history[historyIndex]
        } else {
            historyIndex = history.count
            return ""
        }
    }
}
