// TerminalOutputView.swift
// Adventurers Harness — Full-featured Interactive Terminal & Command Runner Panel

import SwiftUI
import Foundation

// MARK: - Models

public struct TerminalLine: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let content: String
    public let type: LineType

    public enum LineType: String, Sendable {
        case command
        case output
        case error
        case info
    }

    public init(id: UUID = UUID(), timestamp: Date = Date(), content: String, type: LineType) {
        self.id = id
        self.timestamp = timestamp
        self.content = content
        self.type = type
    }
}

@Observable
@MainActor
public final class TerminalSession: Identifiable {
    public let id: UUID
    public var name: String
    public var lines: [TerminalLine] = []
    public var isRunning: Bool = false
    public var exitCode: Int?
    public var activeProcess: Process?

    public init(id: UUID = UUID(), name: String = "Interactive Shell") {
        self.id = id
        self.name = name
    }

    public func appendCommand(_ command: String) {
        lines.append(TerminalLine(timestamp: Date(), content: command, type: .command))
    }

    public func appendOutput(_ output: String) {
        guard !output.isEmpty else { return }
        for line in output.components(separatedBy: "\n") {
            lines.append(TerminalLine(timestamp: Date(), content: line, type: .output))
        }
    }

    public func appendError(_ error: String) {
        guard !error.isEmpty else { return }
        for line in error.components(separatedBy: "\n") {
            lines.append(TerminalLine(timestamp: Date(), content: line, type: .error))
        }
    }

    public func appendInfo(_ info: String) {
        lines.append(TerminalLine(timestamp: Date(), content: info, type: .info))
    }

    public func finish(exitCode: Int) {
        self.exitCode = exitCode
        self.isRunning = false
        self.activeProcess = nil
        let icon = exitCode == 0 ? "✓" : "✗"
        lines.append(TerminalLine(timestamp: Date(), content: "\(icon) Process completed with exit code \(exitCode)", type: .info))
    }

    public func clear() {
        lines.removeAll()
        exitCode = nil
    }

    public func terminate() {
        if let proc = activeProcess, proc.isRunning {
            proc.terminate()
            appendInfo("Process terminated by user.")
            self.isRunning = false
            self.activeProcess = nil
        }
    }

    /// Run a bash/zsh command in the background and stream output
    public func executeCommand(_ cmd: String, cwd: String? = nil) {
        let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed == "clear" {
            clear()
            return
        }

        appendCommand(trimmed)
        self.isRunning = true
        self.exitCode = nil

        let workDir = cwd ?? FileManager.default.currentDirectoryPath

        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", trimmed]
            process.currentDirectoryURL = URL(fileURLWithPath: workDir)

            var env = ProcessInfo.processInfo.environment
            env["TERM"] = "xterm-256color"
            env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
            process.environment = env

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            let outHandle = outPipe.fileHandleForReading
            let errHandle = errPipe.fileHandleForReading

            outHandle.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor [weak self] in
                    self?.appendOutput(str)
                }
            }

            errHandle.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor [weak self] in
                    self?.appendError(str)
                }
            }

            do {
                try process.run()
                await MainActor.run { [weak self] in
                    self?.activeProcess = process
                }
                process.waitUntilExit()
                outHandle.readabilityHandler = nil
                errHandle.readabilityHandler = nil

                let code = Int(process.terminationStatus)
                await MainActor.run { [weak self] in
                    self?.finish(exitCode: code)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.appendError("Failed to launch command: \(error.localizedDescription)")
                    self?.finish(exitCode: 1)
                }
            }
        }
    }
}

@Observable
@MainActor
public final class TerminalManager {
    public var sessions: [TerminalSession] = []
    public var selectedSessionID: UUID?
    public var isExpanded: Bool = true

    public init() {
        let initial = createSession(name: "Interactive Shell")
        initial.appendInfo("Adventurers Terminal Session initialized in \(FileManager.default.currentDirectoryPath)")
        initial.appendInfo("Type commands below or click quick action chips to run tests, git, or build tools.")
    }

    public var activeSession: TerminalSession? {
        guard let id = selectedSessionID else { return sessions.first }
        return sessions.first { $0.id == id } ?? sessions.first
    }

    @discardableResult
    public func createSession(name: String = "Shell") -> TerminalSession {
        let session = TerminalSession(name: name)
        sessions.append(session)
        selectedSessionID = session.id
        return session
    }

    public func logCommand(_ command: String) {
        let session = activeSession ?? createSession(name: "Agent Task")
        session.appendCommand(command)
    }

    public func logOutput(_ output: String) {
        let session = activeSession ?? createSession(name: "Agent Task")
        session.appendOutput(output)
    }

    public func logError(_ error: String) {
        let session = activeSession ?? createSession(name: "Agent Task")
        session.appendError(error)
    }

    public func closeSession(_ session: TerminalSession) {
        session.terminate()
        sessions.removeAll { $0.id == session.id }
        if selectedSessionID == session.id {
            selectedSessionID = sessions.first?.id
        }
        if sessions.isEmpty {
            _ = createSession(name: "Shell 1")
        }
    }
}

// MARK: - Terminal Workbench View

public struct TerminalOutputView: View {
    @Bindable var manager: TerminalManager

    @State private var inputCommand: String = ""
    @State private var searchText: String = ""
    @State private var showSearch: Bool = false
    @State private var wordWrap: Bool = true
    @State private var renamingSession: TerminalSession?
    @State private var renameSessionText: String = ""
    @State private var commandHistory: [String] = []
    @State private var historyIndex: Int = -1

    public init(manager: TerminalManager) {
        self.manager = manager
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Toolbar
            terminalToolbar

            Divider()
                .overlay(Color.adOverlay)

            // Search Bar (if visible)
            if showSearch {
                searchBarView
                Divider().overlay(Color.adOverlay)
            }

            // Session Tabs Bar
            sessionTabsView

            Divider()
                .overlay(Color.adOverlay)

            // Quick Execution Action Chips
            quickActionsBar

            Divider()
                .overlay(Color.adOverlay)

            // Output Monospaced Console Area
            outputScrollArea

            Divider()
                .overlay(Color.adOverlay)

            // Bottom Interactive Command Prompt
            interactiveInputBar
        }
        .background(Color.adBackground)
        .alert("Rename Terminal Session", isPresented: Binding(
            get: { renamingSession != nil },
            set: { if !$0 { renamingSession = nil } }
        )) {
            TextField("Session Name", text: $renameSessionText)
            Button("Save") {
                if let s = renamingSession, !renameSessionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    s.name = renameSessionText.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                renamingSession = nil
            }
            Button("Cancel", role: .cancel) {
                renamingSession = nil
            }
        }
    }

    // MARK: - Toolbar

    private var terminalToolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.adOrange)

                Text("Interactive Terminal & Runner")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.adTextPrimary)
            }

            if let session = manager.activeSession {
                HStack(spacing: 4) {
                    Circle()
                        .fill(session.isRunning ? Color.adOrange : (session.exitCode == 0 ? Color.adSuccess : (session.exitCode != nil ? Color.adError : Color.adTextTertiary)))
                        .frame(width: 6, height: 6)

                    Text(session.isRunning ? "Running" : (session.exitCode != nil ? "Exit \(session.exitCode!)" : "Idle"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.adTextSecondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.adElevated)
                .clipShape(Capsule())
            }

            Spacer()

            // Search toggle
            Button {
                withAnimation { showSearch.toggle() }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(showSearch ? Color.adOrange : Color.adTextSecondary)
            }
            .buttonStyle(.plain)
            .help("Search output (⌘F)")

            // Wrap toggle
            Button {
                wordWrap.toggle()
            } label: {
                Image(systemName: wordWrap ? "text.wrap" : "text.alignleft")
                    .font(.system(size: 11))
                    .foregroundStyle(wordWrap ? Color.adOrange : Color.adTextSecondary)
            }
            .buttonStyle(.plain)
            .help("Toggle Word Wrap")

            if let session = manager.activeSession {
                if session.isRunning {
                    Button {
                        session.terminate()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 9))
                            Text("Stop")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(Color.adError)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.adError.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .help("Terminate Running Process")
                }

                Button {
                    copyAllOutput(session)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.adTextSecondary)
                }
                .buttonStyle(.plain)
                .help("Copy Entire Output")

                Button {
                    session.clear()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.adTextSecondary)
                }
                .buttonStyle(.plain)
                .help("Clear Session Log")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.adNavy)
    }

    // MARK: - Search Bar

    private var searchBarView: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.adTextTertiary)
                .font(.caption)

            TextField("Search in terminal logs...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.adTextTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.adElevated)
    }

    // MARK: - Session Tabs

    private var sessionTabsView: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(manager.sessions) { session in
                        sessionTabPill(session)
                    }

                    Button {
                        _ = manager.createSession(name: "Shell \(manager.sessions.count + 1)")
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.adTextSecondary)
                            .padding(6)
                            .background(Color.adElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .help("New Terminal Session")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
        }
        .background(Color.adBackground)
    }

    private func sessionTabPill(_ session: TerminalSession) -> some View {
        let isSelected = manager.selectedSessionID == session.id

        return HStack(spacing: 6) {
            if session.isRunning {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: 9))
                    .foregroundStyle(isSelected ? Color.adOrange : Color.adTextTertiary)
            }

            Text(session.name)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.adTextPrimary : Color.adTextSecondary)

            if let code = session.exitCode {
                Text("\(code)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(code == 0 ? Color.adSuccess.opacity(0.2) : Color.adError.opacity(0.2))
                    .foregroundStyle(code == 0 ? Color.adSuccess : Color.adError)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            if manager.sessions.count > 1 {
                Button {
                    manager.closeSession(session)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.adTextTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSelected ? Color.adElevated : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .onTapGesture {
            manager.selectedSessionID = session.id
        }
        .contextMenu {
            Button("Rename Session") {
                renamingSession = session
                renameSessionText = session.name
            }
            Button("Clear Output") {
                session.clear()
            }
            Divider()
            Button("Close Session", role: .destructive) {
                manager.closeSession(session)
            }
        }
    }

    // MARK: - Quick Action Chips

    private var quickActionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("Self-Dev & Dogfooding:")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.adOrange)
                    .padding(.leading, 4)

                quickChip(label: "🧪 swift test", cmd: "swift test")
                quickChip(label: "🔨 build release", cmd: "swift build -c release --triple arm64-apple-macosx15.0")
                quickChip(label: "📦 package app (dmg/zip/tar)", cmd: "./scripts/package_app.sh 1.0.0")
                quickChip(label: "🔍 git status & log", cmd: "git status && git log -n 5 --oneline")
                quickChip(label: "🛡️ git diff", cmd: "git diff")
                quickChip(label: "🎨 generate icon", cmd: "./scripts/generate_icon.sh")
                quickChip(label: "🧹 clean & rebuild", cmd: "rm -rf .build && swift build")
                quickChip(label: "clear", cmd: "clear")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .background(Color.adNavy.opacity(0.8))
    }

    private func quickChip(label: String, cmd: String) -> some View {
        Button {
            manager.activeSession?.executeCommand(cmd)
        } label: {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.adTextSecondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.adElevated)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Output Console Scroll Area

    private var outputScrollArea: some View {
        ScrollViewReader { proxy in
            ScrollView(wordWrap ? .vertical : [.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if let session = manager.activeSession {
                        if session.lines.isEmpty {
                            HStack {
                                Text("Ready. Type a command below or select a quick action chip.")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Color.adTextTertiary)
                                Spacer()
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(filteredLines) { line in
                                terminalLineRow(line)
                                    .id(line.id)
                            }
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 11, design: .monospaced))
            .background(Color.adNavy)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: manager.activeSession?.lines.count) { _, _ in
                if let last = filteredLines.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Line Row View

    private func terminalLineRow(_ line: TerminalLine) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(timeString(line.timestamp))
                .foregroundStyle(Color.adTextTertiary.opacity(0.6))
                .font(.system(size: 9, design: .monospaced))
                .frame(width: 52, alignment: .leading)

            // Prompt symbol
            Group {
                switch line.type {
                case .command:
                    Text("❯")
                        .foregroundStyle(Color.adOrange)
                        .fontWeight(.bold)
                case .error:
                    Text("✗")
                        .foregroundStyle(Color.adError)
                case .info:
                    Text("ℹ")
                        .foregroundStyle(Color.adTextTertiary)
                case .output:
                    Text(" ")
                        .foregroundStyle(.clear)
                }
            }
            .frame(width: 12, alignment: .center)

            // Content
            Text(line.content)
                .textSelection(.enabled)
                .foregroundStyle(lineColor(line.type))
                .lineLimit(wordWrap ? nil : 1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
        .background(line.type == .command ? Color.adElevated.opacity(0.4) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    // MARK: - Interactive Input Bar

    private var interactiveInputBar: some View {
        HStack(spacing: 8) {
            Text("❯")
                .foregroundStyle(Color.adOrange)
                .font(.system(size: 13, weight: .bold, design: .monospaced))

            TextField("Type a bash command (e.g. swift test, git status)...", text: $inputCommand)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.adTextPrimary)
                .onSubmit {
                    submitCommand()
                }

            if !inputCommand.isEmpty {
                Button {
                    submitCommand()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.adOrange)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.adElevated)
    }

    private func submitCommand() {
        let cmd = inputCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        commandHistory.append(cmd)
        historyIndex = commandHistory.count
        inputCommand = ""
        manager.activeSession?.executeCommand(cmd)
    }

    // MARK: - Helpers

    private var filteredLines: [TerminalLine] {
        guard let session = manager.activeSession else { return [] }
        if searchText.isEmpty { return session.lines }
        return session.lines.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
    }

    private func lineColor(_ type: TerminalLine.LineType) -> Color {
        switch type {
        case .command: return Color.adTextPrimary
        case .error:   return Color.adError
        case .info:    return Color.adOrange
        case .output:  return Color.adTextSecondary
        }
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func copyAllOutput(_ session: TerminalSession) {
        let text = session.lines.map { "[\(timeString($0.timestamp))] \($0.content)" }.joined(separator: "\n")
        #if os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        #endif
    }
}
