// TUI - Permission Dialog
// Bottom-sheet permission request panel inspired by Codex's permission system.
// Asks for permission to run commands that require elevated permissions
// like network access, file writes, or shell execution.

import SwiftUI
import AdventurersCore

// MARK: - Permission Request Model

/// A single permission request from an agent or tool invocation.
public struct PermissionRequest: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let toolName: String
    public let riskLevel: RiskLevel
    public let command: String
    public let agentID: String
    public let threadID: String?
    public let timestamp: Date
    public let context: String?

    public init(
        id: UUID = UUID(),
        toolName: String,
        riskLevel: RiskLevel,
        command: String,
        agentID: String,
        threadID: String? = nil,
        timestamp: Date = Date(),
        context: String? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.riskLevel = riskLevel
        self.command = command
        self.agentID = agentID
        self.threadID = threadID
        self.timestamp = timestamp
        self.context = context
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: PermissionRequest, rhs: PermissionRequest) -> Bool {
        lhs.id == rhs.id
    }
}

/// The user's decision on a permission request.
public enum PermissionDecision: Sendable {
    case allowOnce
    case allowForSession
    case deny
}

/// A recorded permission decision for history display.
public struct PermissionRecord: Sendable, Identifiable {
    public let id: UUID
    public let request: PermissionRequest
    public let decision: PermissionDecision
    public let decidedAt: Date

    public init(request: PermissionRequest, decision: PermissionDecision, decidedAt: Date = Date()) {
        self.id = UUID()
        self.request = request
        self.decision = decision
        self.decidedAt = decidedAt
    }
}

// MARK: - Permission State (Observable)

/// Observable state container for the permission dialog system.
/// Manages the active request, history, timer, and session-level allowances.
@Observable
@MainActor
public final class PermissionState: @unchecked Sendable {
    /// The currently active permission request, or nil if no dialog is showing.
    public var activeRequest: PermissionRequest?

    /// Whether the dialog is visible (controls slide-up animation).
    public var isPresented: Bool = false

    /// The "Don't ask again for this tool" toggle state.
    public var suppressForTool: Bool = false

    /// Remaining seconds on the auto-deny countdown.
    public var countdown: Int = 30

    /// Maximum countdown duration in seconds.
    public let maxCountdown: Int = 30

    /// Recent permission history (newest first).
    public var history: [PermissionRecord] = []

    /// Whether the history section is expanded.
    public var isHistoryExpanded: Bool = false

    /// Tool names that have been permanently suppressed (allow without asking).
    public var suppressedTools: Set<String> = []

    /// Tool names allowed for the current session only.
    public var sessionAllowedTools: Set<String> = []

    /// Pending decision callback — set by the dialog, consumed by the caller.
    public var onDecision: (@Sendable (PermissionDecision) -> Void)?

    private var countdownTask: Task<Void, Never>?

    public init() {}

    // MARK: - Presentation

    /// Present the dialog for a new permission request.
    public func present(_ request: PermissionRequest) {
        // If this tool is suppressed or session-allowed, auto-approve.
        if suppressedTools.contains(request.toolName) || sessionAllowedTools.contains(request.toolName) {
            let record = PermissionRecord(
                request: request,
                decision: .allowForSession,
                decidedAt: Date()
            )
            history.insert(record, at: 0)
            onDecision?(.allowForSession)
            return
        }

        activeRequest = request
        isPresented = true
        suppressForTool = false
        countdown = maxCountdown
        startCountdown()
    }

    /// Dismiss the current dialog and record the decision.
    public func decide(_ decision: PermissionDecision) {
        guard let request = activeRequest else { return }

        let record = PermissionRecord(request: request, decision: decision, decidedAt: Date())
        history.insert(record, at: 0)

        if suppressForTool {
            switch decision {
            case .allowOnce, .allowForSession:
                suppressedTools.insert(request.toolName)
            case .deny:
                break
            }
        } else if decision == .allowForSession {
            sessionAllowedTools.insert(request.toolName)
        }

        stopCountdown()
        isPresented = false
        activeRequest = nil
        onDecision?(decision)
        onDecision = nil
    }

    /// Cancel presentation without deciding (used by timer expiry).
    public func cancel() {
        decide(.deny)
    }

    // MARK: - Countdown Timer

    private func startCountdown() {
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            guard let self else { return }
            for second in stride(from: self.maxCountdown, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.countdown = second
                }
                if second == 0 {
                    await MainActor.run {
                        self.cancel()
                    }
                    return
                }
            }
        }
    }

    private func stopCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
    }

    deinit {
        countdownTask?.cancel()
    }
}

// MARK: - Risk Level Presentation Helpers

extension RiskLevel {
    /// Display name for the risk level badge.
    var displayLabel: String {
        switch self {
        case .readOnly:     return "Read Only"
        case .network:      return "Network"
        case .write:        return "Write"
        case .execute:      return "Execute"
        case .destructive:  return "Destructive"
        }
    }

    /// SF Symbol name for the risk level.
    var iconName: String {
        switch self {
        case .readOnly:     return "eye"
        case .network:      return "network"
        case .write:        return "pencil.and.list.clipboard"
        case .execute:      return "terminal"
        case .destructive:  return "exclamationmark.triangle.fill"
        }
    }

    /// Lock icon required for high-risk operations.
    var requiresLock: Bool {
        self >= .execute
    }
}

// MARK: - Color Helpers

extension RiskLevel {
    /// Primary color for the risk level.
    var color: Color {
        switch self {
        case .readOnly:     return .blue
        case .network:      return .yellow
        case .write:        return .orange
        case .execute:      return .red
        case .destructive:  return .crimson
        }
    }

    /// Background color for the risk badge (slightly desaturated).
    var badgeBackgroundColor: Color {
        switch self {
        case .readOnly:     return Color.blue.opacity(0.15)
        case .network:      return Color.yellow.opacity(0.15)
        case .write:        return Color.orange.opacity(0.15)
        case .execute:      return Color.red.opacity(0.15)
        case .destructive:  return Color.crimson.opacity(0.15)
        }
    }
}

// MARK: - Main Dialog View

/// A floating permission request panel that slides up from the bottom.
///
/// Shows the tool name, risk level badge, command preview, source context,
/// and action buttons. Includes a countdown timer that auto-denies after 30 seconds.
public struct PermissionDialogView: View {
    @Bindable var state: PermissionState
    let onDecision: (PermissionDecision) -> Void

    public init(state: PermissionState, onDecision: @escaping @Sendable (PermissionDecision) -> Void) {
        self.state = state
        self.onDecision = onDecision
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            // Dimmed backdrop
            if state.isPresented {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        state.decide(.deny)
                    }
                    .transition(.opacity)
            }

            // Dialog panel
            if let request = state.activeRequest {
                dialogPanel(request: request)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .keyboardShortcut(.cancelAction)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: state.isPresented)
        .onChange(of: state.isPresent) { _, newValue in
            if newValue {
                state.onDecision = { decision in
                    onDecision(decision)
                }
            }
        }
        .onKeyPress(.escape) {
            if state.isPresent {
                state.decide(.deny)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.return) {
            if state.isPresent {
                state.decide(.allowOnce)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.upArrow) {
            // Shift+Enter produces .return with shift modifier in SwiftUI;
            // intercepting raw modifier state is limited, so we also map
            // a dedicated key chord as a fallback.
            return .ignored
        }
    }

    // MARK: - Dialog Panel

    @ViewBuilder
    private func dialogPanel(request: PermissionRequest) -> some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header: tool name + risk badge + lock
                    headerRow(request: request)

                    // Agent / thread context
                    sourceContext(request: request)

                    // Command preview
                    CommandPreviewView(command: request.command, riskLevel: request.riskLevel)

                    // Suppress checkbox
                    suppressToggle

                    // Action buttons
                    actionButtons

                    // Countdown overlay
                    countdownBar
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .frame(maxHeight: 400)

            Divider()

            // History section
            PermissionHistoryView(state: state)
        }
        .background(DialogBackground())
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 20, y: -4)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: 560)
    }

    // MARK: - Header

    @ViewBuilder
    private func headerRow(request: PermissionRequest) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(request.toolName)
                        .font(.title3.bold())
                        .foregroundStyle(.primary)

                    if request.riskLevel.requiresLock {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(request.riskLevel.color)
                            .accessibilityLabel("High-risk operation")
                    }
                }

                Text("Permission requested")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            RiskBadgeView(riskLevel: request.riskLevel)
        }
    }

    // MARK: - Source Context

    @ViewBuilder
    private func sourceContext(request: PermissionRequest) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "person.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Agent: \(request.agentID)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                if let threadID = request.threadID {
                    Text("Thread: \(threadID)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if let context = request.context {
                Text(context)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text(request.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Suppress Toggle

    private var suppressToggle: some View {
        HStack(spacing: 8) {
            Image(systemName: state.suppressForTool ? "checkmark.circle.fill" : "circle")
                .font(.body)
                .foregroundStyle(state.suppressForTool ? .accentColor : .secondary)
                .contentShape(Rectangle())
                .onTapGesture {
                    state.suppressForTool.toggle()
                }

            Text("Don't ask again for this tool")
                .font(.callout)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
                .onTapGesture {
                    state.suppressForTool.toggle()
                }

            Spacer()
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Deny
            Button {
                state.decide(.deny)
            } label: {
                Label("Deny", systemImage: "xmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
            .keyboardShortcut(.cancelAction)

            // Allow Once
            Button {
                state.decide(.allowOnce)
            } label: {
                Label("Allow Once", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .keyboardShortcut(.defaultAction)

            // Allow for Session
            Button {
                state.decide(.allowForSession)
            } label: {
                Label("Allow Session", systemImage: "checkmark.seal.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.green)
        }
    }

    // MARK: - Countdown Bar

    @ViewBuilder
    private var countdownBar: some View {
        if state.countdown > 0 && state.countdown < state.maxCountdown {
            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.1))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(state.countdown <= 10 ? Color.red : Color.accentColor)
                            .frame(
                                width: geo.size.width * CGFloat(state.countdown) / CGFloat(state.maxCountdown),
                                height: 4
                            )
                            .animation(.linear(duration: 1), value: state.countdown)
                    }
                }
                .frame(height: 4)

                HStack {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text("Auto-deny in \(state.countdown)s")
                        .font(.caption2)
                }
                .foregroundStyle(state.countdown <= 10 ? .red : .secondary)
            }
        }
    }
}

// MARK: - Risk Badge View

/// A color-coded badge displaying the risk level with an icon and label.
public struct RiskBadgeView: View {
    let riskLevel: RiskLevel

    public init(riskLevel: RiskLevel) {
        self.riskLevel = riskLevel
    }

    public var body: some View {
        HStack(spacing: 5) {
            Image(systemName: riskLevel.iconName)
                .font(.caption2.bold())

            Text(riskLevel.displayLabel)
                .font(.caption.bold())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(riskLevel.color)
        .background(riskLevel.badgeBackgroundColor)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(riskLevel.color.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Command Preview View

/// Displays a command with basic syntax highlighting and truncation for long output.
public struct CommandPreviewView: View {
    let command: String
    let riskLevel: RiskLevel

    /// Maximum number of lines to show before truncation.
    private let maxLines: Int = 8

    public init(command: String, riskLevel: RiskLevel) {
        self.command = command
        self.riskLevel = riskLevel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "terminal.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("Command Preview")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Spacer()

                if command.count > 200 {
                    Text("\(command.count) chars")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            ScrollView(.vertical, showsIndicators: false) {
                highlightedText
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: CGFloat(maxLines) * 18)
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(riskLevel.color.opacity(0.2), lineWidth: 1)
            )
        }
    }

    /// Basic syntax highlighting for shell commands.
    private var highlightedText: some View {
        var result = AttributedString(command)

        // Highlight common shell keywords
        let keywords = ["sudo", "rm", "mv", "cp", "chmod", "chown", "kill",
                        "curl", "wget", "ssh", "scp", "rsync", "git",
                        "docker", "npm", "pip", "brew", "apt", "yum"]
        let dangerousPatterns = ["rm -rf", "rm -fr", "force push", "--force",
                                 "DROP TABLE", "DELETE FROM", "FORMAT"]

        // Apply keyword highlighting
        for keyword in keywords {
            if let range = result.range(of: keyword) {
                result[range].foregroundColor = .orange
                result[range].font = .caption.monospaced().bold()
            }
        }

        // Highlight dangerous patterns
        for pattern in dangerousPatterns {
            if let range = result.range(of: pattern, options: .caseInsensitive) {
                result[range].foregroundColor = .red
                result[range].font = .caption.monospaced().bold()
                result[range].underlineStyle = .single
            }
        }

        // Highlight flags (words starting with -)
        let words = command.split(separator: " ")
        for word in words where word.hasPrefix("-") {
            if let range = result.range(of: String(word)) {
                result[range].foregroundColor = .cyan
            }
        }

        // Highlight pipe characters
        if let range = result.range(of: "|") {
            result[range].foregroundColor = .purple
            result[range].font = .caption.monospaced().bold()
        }

        // Highlight quoted strings
        let quotePattern = #""[^"]*""#
        if let regex = try? NSRegularExpression(pattern: quotePattern),
           let match = regex.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)) {
            if let swiftRange = Range(match.range, in: command),
               let attrRange = result.range(of: String(command[swiftRange])) {
                result[attrRange].foregroundColor = .green
            }
        }

        return Text(result)
    }
}

// MARK: - Permission History View

/// Expandable section showing recent permission decisions.
public struct PermissionHistoryView: View {
    @Bindable var state: PermissionState

    public init(state: PermissionState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Toggle header
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    state.isHistoryExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption)
                    Text("Recent Permissions (\(state.history.count))")
                        .font(.caption.bold())
                    Spacer()
                    Image(systemName: state.isHistoryExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if state.isHistoryExpanded {
                Divider()

                if state.history.isEmpty {
                    Text("No permission history yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(state.history.prefix(20)) { record in
                                historyRow(record: record)
                                if record.id != state.history.prefix(20).last?.id {
                                    Divider()
                                        .padding(.horizontal, 20)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }
        }
    }

    @ViewBuilder
    private func historyRow(record: PermissionRecord) -> some View {
        HStack(spacing: 10) {
            // Decision icon
            decisionIcon(record.decision)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(record.request.toolName)
                        .font(.caption.bold())
                        .foregroundStyle(.primary)

                    RiskBadgeView(riskLevel: record.request.riskLevel)
                        .scaleEffect(0.8)
                        .frame(alignment: .center)
                }

                Text(record.request.command)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                decisionLabel(record.decision)
                    .font(.caption2.bold())

                Text(record.decidedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func decisionIcon(_ decision: PermissionDecision) -> some View {
        switch decision {
        case .allowOnce:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .allowForSession:
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.blue)
        case .deny:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func decisionLabel(_ decision: PermissionDecision) -> some View {
        switch decision {
        case .allowOnce:
            Text("Allowed")
                .foregroundStyle(.green)
        case .allowForSession:
            Text("Session")
                .foregroundStyle(.blue)
        case .deny:
            Text("Denied")
                .foregroundStyle(.red)
        }
    }
}

// MARK: - Dialog Background

/// Translucent background for the dialog panel.
private struct DialogBackground: View {
    var body: some View {
        if #available(macOS 15.0, *) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        }
    }
}

// MARK: - Keyboard Shortcut Helpers

/// Keyboard shortcut for the Deny action (Escape).
private struct DenyKeyShortcut: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .onKeyPress(.escape) {
                action()
                return .handled
            }
    }
}

/// Keyboard shortcut for Allow Once (Enter).
private struct AllowOnceKeyShortcut: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .onKeyPress(.return) {
                action()
                return .handled
            }
    }
}

/// Keyboard shortcut for Allow Session (Shift+Enter).
private struct AllowSessionKeyShortcut: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .onKeyPress("Return", modifiers: .shift) {
                action()
                return .handled
            }
    }
}

extension View {
    /// Applies deny-on-escape keyboard shortcut.
    func denyOnEscape(action: @escaping () -> Void) -> some View {
        modifier(DenyKeyShortcut(action: action))
    }

    /// Applies allow-on-enter keyboard shortcut.
    func allowOnReturn(action: @escaping () -> Void) -> some View {
        modifier(AllowOnceKeyShortcut(action: action))
    }

    /// Applies allow-session-on-shift-enter keyboard shortcut.
    func allowSessionOnShiftReturn(action: @escaping () -> Void) -> some View {
        modifier(AllowSessionKeyShortcut(action: action))
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Permission Dialog") {
    @Previewable @State var state = PermissionState()
    @Previewable @State var lastDecision: String = "None"

    VStack(spacing: 20) {
        Text("Last decision: \(lastDecision)")
            .font(.headline)

        Button("Show Read-Only Request") {
            state.present(PermissionRequest(
                toolName: "grep",
                riskLevel: .readOnly,
                command: "grep -rn \"TODO\" ./Sources/",
                agentID: "planner-01"
            ))
        }

        Button("Show Network Request") {
            state.present(PermissionRequest(
                toolName: "curl",
                riskLevel: .network,
                command: "curl -s https://api.github.com/repos/swift/swift/issues",
                agentID: "researcher-03",
                context: "Fetching issue data"
            ))
        }

        Button("Show Write Request") {
            state.present(PermissionRequest(
                toolName: "file_edit",
                riskLevel: .write,
                command: "edit Sources/AdventurersCore/AgentLoop.swift:42",
                agentID: "coder-02",
                threadID: "thread-a1b2"
            ))
        }

        Button("Show Execute Request") {
            state.present(PermissionRequest(
                toolName: "bash",
                riskLevel: .execute,
                command: "swift build --package-path /Users/dev/project 2>&1 | tail -20",
                agentID: "builder-01",
                context: "Compiling after patch"
            ))
        }

        Button("Show Destructive Request") {
            state.present(PermissionRequest(
                toolName: "bash",
                riskLevel: .destructive,
                command: "rm -rf ./build/ && git push --force origin main",
                agentID: "deployer-01",
                context: "Cleaning build artifacts"
            ))
        }
    }
    .padding()
    .frame(width: 700, height: 500)
    .overlay {
        PermissionDialogView(state: state) { decision in
            lastDecision = "\(decision)"
        }
    }
}
#endif
