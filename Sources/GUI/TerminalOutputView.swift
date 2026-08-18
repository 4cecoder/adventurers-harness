// TerminalOutputView.swift
// Adventurers Harness — GUI output panel for agent bash executions.
// Not a terminal emulator — a styled output viewer with command/result display.

import SwiftUI

// MARK: - Models

/// A single line of terminal output.
struct TerminalLine: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let content: String
    let type: LineType

    enum LineType: String, Sendable {
        case command
        case output
        case error
        case info
    }
}

/// A terminal session capturing one bash execution.
@Observable
@MainActor
final class TerminalSession {
    let id = UUID()
    var name: String
    var lines: [TerminalLine] = []
    var isRunning: Bool = false
    var exitCode: Int?

    init(name: String = "Session") {
        self.name = name
    }

    func appendCommand(_ command: String) {
        lines.append(TerminalLine(timestamp: Date(), content: command, type: .command))
    }

    func appendOutput(_ output: String) {
        guard !output.isEmpty else { return }
        for line in output.components(separatedBy: "\n") {
            lines.append(TerminalLine(timestamp: Date(), content: line, type: .output))
        }
    }

    func appendError(_ error: String) {
        guard !error.isEmpty else { return }
        for line in error.components(separatedBy: "\n") {
            lines.append(TerminalLine(timestamp: Date(), content: line, type: .error))
        }
    }

    func finish(exitCode: Int) {
        self.exitCode = exitCode
        self.isRunning = false
        let icon = exitCode == 0 ? "✓" : "✗"
        lines.append(TerminalLine(timestamp: Date(), content: "\(icon) Process exited with code \(exitCode)", type: .info))
    }

    func clear() {
        lines.removeAll()
        exitCode = nil
    }
}

/// Manages multiple terminal sessions.
@Observable
@MainActor
final class TerminalManager {
    var sessions: [TerminalSession] = []
    var selectedSessionID: UUID?
    var isExpanded: Bool = false

    var activeSession: TerminalSession? {
        guard let id = selectedSessionID else { return sessions.first }
        return sessions.first { $0.id == id }
    }

    func createSession(name: String = "Session") -> TerminalSession {
        let session = TerminalSession(name: name)
        sessions.append(session)
        selectedSessionID = session.id
        return session
    }

    func closeSession(_ session: TerminalSession) {
        sessions.removeAll { $0.id == session.id }
        if selectedSessionID == session.id {
            selectedSessionID = sessions.first?.id
        }
    }
}

// MARK: - Main View

/// A collapsible GUI panel showing agent command execution output.
/// Renders at the bottom of the thread view — not a real terminal.
struct TerminalOutputView: View {
    @Bindable var manager: TerminalManager

    @State private var searchText: String = ""
    @State private var showSearch: Bool = false
    @State private var wordWrap: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            if manager.isExpanded {
                expandedView
            } else {
                collapsedBar
            }
        }
        .animation(.spring(response: 0.3), value: manager.isExpanded)
    }

    // MARK: - Expanded View

    private var expandedView: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if showSearch { searchBar; Divider() }
            sessionTabs
            Divider()
            outputScrollArea
            Divider()
            inputBar
        }
        .frame(minHeight: 200, idealHeight: 300)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Label("Output", systemImage: "terminal")
                .font(.headline)

            Spacer()

            Button { showSearch.toggle() } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.plain)
            .help("Search output")

            Toggle(isOn: $wordWrap) {
                Image(systemName: "text.wrap")
            }
            .toggleStyle(.plain)
            .buttonStyle(.plain)
            .help("Word wrap")

            if let session = manager.activeSession {
                Button {
                    copyLastCommand(session)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .help("Copy last command")

                Button {
                    session.clear()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Clear session")
            }

            Divider().frame(height: 16)

            Button { manager.isExpanded = false } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .help("Collapse panel")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search output...", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Session Tabs

    private var sessionTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(manager.sessions) { session in
                    sessionTab(session)
                }
                Button { _ = manager.createSession() } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private func sessionTab(_ session: TerminalSession) -> some View {
        Button { manager.selectedSessionID = session.id } label: {
            HStack(spacing: 6) {
                if session.isRunning {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text(session.name)
                    .font(.caption)
                    .lineLimit(1)
                if let code = session.exitCode {
                    Text("\(code)")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(code == 0 ? .green.opacity(0.2) : .red.opacity(0.2), in: Capsule())
                        .foregroundStyle(code == 0 ? .green : .red)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                manager.selectedSessionID == session.id
                    ? Color.accentColor.opacity(0.15)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename") { /* TODO */ }
            Button("Clear") { session.clear() }
            Divider()
            Button("Close") { manager.closeSession(session) }
        }
    }

    // MARK: - Output Scroll Area

    private var outputScrollArea: some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(filteredLines) { line in
                        terminalLineView(line)
                            .id(line.id)
                    }
                }
                .padding(8)
            }
            .font(.system(.body, design: .monospaced))
            .onChange(of: manager.activeSession?.lines.count) { _, _ in
                withAnimation { scrollToBottom(proxy) }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let lastLine = filteredLines.last {
            proxy.scrollTo(lastLine.id, anchor: .bottom)
        }
    }

    // MARK: - Line View

    private func terminalLineView(_ line: TerminalLine) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(timeString(line.timestamp))
                .foregroundStyle(.tertiary)
                .font(.caption2)
                .frame(width: 60, alignment: .leading)

            // Prompt indicator
            switch line.type {
            case .command:
                Text("❯")
                    .foregroundStyle(.green)
                    .bold()
            case .error:
                Text("✗")
                    .foregroundStyle(.red)
            case .output, .info:
                Text(" ")
                    .foregroundStyle(.secondary)
            }

            // Content
            Text(line.content)
                .textSelection(.enabled)
                .foregroundStyle(lineColor(line.type))
                .lineSpacing(2)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(
            line.type == .command
                ? Color.green.opacity(0.05)
                : Color.clear
        )
    }

    private func lineColor(_ type: TerminalLine.LineType) -> Color {
        switch type {
        case .command: return .green
        case .error:   return .red
        case .output:  return .primary
        case .info:    return .secondary
        }
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            Text("$")
                .foregroundStyle(.green)
                .font(.system(.body, design: .monospaced).bold())

            TextField("Enter command...", text: .constant(""))
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .onSubmit { /* TODO: execute command */ }
        }
        .padding(8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Collapsed Bar

    private var collapsedBar: some View {
        Button { manager.isExpanded = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .foregroundStyle(.secondary)
                if let session = manager.activeSession {
                    Text("\(session.lines.count) lines")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let code = session.exitCode {
                        Text("exit \(code)")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(code == 0 ? .green.opacity(0.2) : .red.opacity(0.2), in: Capsule())
                            .foregroundStyle(code == 0 ? .green : .red)
                    }
                } else {
                    Text("No sessions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var filteredLines: [TerminalLine] {
        guard let session = manager.activeSession else { return [] }
        if searchText.isEmpty { return session.lines }
        return session.lines.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
    }

    private func copyLastCommand(_ session: TerminalSession) {
        guard let lastCommand = session.lines.last(where: { $0.type == .command }) else { return }
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastCommand.content, forType: .string)
        #endif
    }
}
