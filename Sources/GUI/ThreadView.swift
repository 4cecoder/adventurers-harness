// TUI - ThreadView
// Center content area: scrollable message list with agent/user messages,
// tool execution indicators, code blocks, streaming, and gate progress.

import SwiftUI
import AdventurersCore

// MARK: - Thread Message Model

/// A single message in the thread, representing either user input or agent output.
/// Wraps core domain types into a UI-ready, observable representation.
public struct ThreadMessage: Identifiable, Sendable {
    public let id: String
    public let role: MessageRole
    public let content: String
    public let timestamp: Date
    public let toolCalls: [ThreadToolCall]
    public let toolResults: [ThreadToolResult]
    public let isStreaming: Bool
    public let thinkingContent: String?

    public enum MessageRole: Sendable {
        case user
        case agent
        case system
        case gateResult
    }

    public init(
        id: String = UUID().uuidString,
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        toolCalls: [ThreadToolCall] = [],
        toolResults: [ThreadToolResult] = [],
        isStreaming: Bool = false,
        thinkingContent: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        self.isStreaming = isStreaming
        self.thinkingContent = thinkingContent
    }
}

/// A tool call embedded in an agent message, displayed as an inline preview.
public struct ThreadToolCall: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let arguments: String
    public let status: ToolCallStatus

    public enum ToolCallStatus: Sendable {
        case pending
        case running
        case succeeded(output: String)
        case failed(error: String)
    }

    public init(
        id: String = UUID().uuidString,
        name: String,
        arguments: String,
        status: ToolCallStatus = .pending
    ) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.status = status
    }
}

/// The result of a completed tool execution.
public struct ThreadToolResult: Identifiable, Sendable {
    public let id: String
    public let toolCallID: String
    public let output: String
    public let isError: Bool

    public init(id: String = UUID().uuidString, toolCallID: String, output: String, isError: Bool = false) {
        self.id = id
        self.toolCallID = toolCallID
        self.output = output
        self.isError = isError
    }
}

/// Gate progress for the horizontal progress bar at the top of the thread.
public struct GateProgress: Sendable {
    public let name: String
    public let displayName: String
    public let status: GateStatus

    public enum GateStatus: Sendable {
        case pending
        case running
        case passed
        case failed(error: String)
    }

    public init(name: String, displayName: String, status: GateStatus = .pending) {
        self.name = name
        self.displayName = displayName
        self.status = status
    }
}

// MARK: - Thread ViewModel

/// The observable state for the entire thread view.
/// Manages messages, gate progress, streaming state, and input.
@Observable
@MainActor
public final class ThreadViewModel {
    public var messages: [ThreadMessage] = []
    public var gateProgress: [GateProgress] = [
        GateProgress(name: "syntax", displayName: "Syntax Gate"),
        GateProgress(name: "repeat", displayName: "Repeat Gate"),
        GateProgress(name: "compilation", displayName: "Compilation Gate"),
    ]
    public var inputText: String = ""
    public var selectedModel: String = "gpt-4o"
    public var isGenerating: Bool = false
    public var isLoadingSkeleton: Bool = true
    public var availableModels: [String] = [
        "gpt-4o",
        "gpt-4o-mini",
        "claude-sonnet-4-20250514",
        "claude-3-5-haiku-20241022",
    ]

    /// The most recent streaming message ID, used for auto-scroll.
    public var lastStreamingMessageID: String?

    public init() {
        loadPlaceholderMessages()
    }

    // MARK: - Public API

    /// Append a new message to the thread.
    public func appendMessage(_ message: ThreadMessage) {
        messages.append(message)
        if message.isStreaming {
            lastStreamingMessageID = message.id
        }
        isLoadingSkeleton = false
    }

    /// Update an existing message by ID (used during streaming).
    public func updateMessage(id: String, content: String, toolCalls: [ThreadToolCall]? = nil) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        let old = messages[index]
        messages[index] = ThreadMessage(
            id: old.id,
            role: old.role,
            content: content,
            timestamp: old.timestamp,
            toolCalls: toolCalls ?? old.toolCalls,
            toolResults: old.toolResults,
            isStreaming: old.isStreaming,
            thinkingContent: old.thinkingContent
        )
    }

    /// Mark a message as no longer streaming.
    public func finishStreaming(messageID: String) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        let old = messages[index]
        messages[index] = ThreadMessage(
            id: old.id,
            role: old.role,
            content: old.content,
            timestamp: old.timestamp,
            toolCalls: old.toolCalls,
            toolResults: old.toolResults,
            isStreaming: false,
            thinkingContent: old.thinkingContent
        )
        if lastStreamingMessageID == messageID {
            lastStreamingMessageID = nil
        }
    }

    /// Update gate progress by name.
    public func updateGate(name: String, status: GateProgress.GateStatus) {
        guard let index = gateProgress.firstIndex(where: { $0.name == name }) else { return }
        gateProgress[index] = GateProgress(
            name: gateProgress[index].name,
            displayName: gateProgress[index].displayName,
            status: status
        )
    }

    /// Reset all gates to pending.
    public func resetGates() {
        gateProgress = [
            GateProgress(name: "syntax", displayName: "Syntax Gate"),
            GateProgress(name: "repeat", displayName: "Repeat Gate"),
            GateProgress(name: "compilation", displayName: "Compilation Gate"),
        ]
    }

    /// Send the current input as a user message.
    public func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }

        let userMessage = ThreadMessage(role: .user, content: text)
        appendMessage(userMessage)
        inputText = ""
        isGenerating = true
    }

    /// Clear the entire thread.
    public func clearThread() {
        messages.removeAll()
        gateProgress = [
            GateProgress(name: "syntax", displayName: "Syntax Gate"),
            GateProgress(name: "repeat", displayName: "Repeat Gate"),
            GateProgress(name: "compilation", displayName: "Compilation Gate"),
        ]
        isGenerating = false
        isLoadingSkeleton = true
        lastStreamingMessageID = nil
    }

    // MARK: - Placeholder Data

    private func loadPlaceholderMessages() {
        // Show loading skeleton initially; cleared when real messages arrive.
    }
}

// MARK: - ThreadView (Root)

/// The main thread content view: gate progress, scrollable messages, and input bar.
public struct ThreadView: View {
    @State private var viewModel = ThreadViewModel()
    @State private var hoveredMessageID: String?
    @State private var showingModelPicker = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            GateProgressView(gates: viewModel.gateProgress)

            Divider()

            messagesArea

            Divider()

            MessageInputBar(
                text: $viewModel.inputText,
                selectedModel: $viewModel.selectedModel,
                availableModels: viewModel.availableModels,
                isGenerating: viewModel.isGenerating,
                onSend: { viewModel.sendMessage() },
                onClear: { viewModel.clearThread() }
            )
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Messages Area

    @ViewBuilder
    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if viewModel.isLoadingSkeleton {
                        LoadingSkeletonView()
                    } else if viewModel.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(viewModel.messages) { message in
                            MessageBubbleView(
                                message: message,
                                isHovered: hoveredMessageID == message.id,
                                onRetry: { retryMessage(message) },
                                onCopy: { copyMessage(message) },
                                onDelete: { deleteMessage(message) }
                            )
                            .id(message.id)
                            .onHover { isHovered in
                                hoveredMessageID = isHovered ? message.id : nil
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.automatic)
            .onChange(of: viewModel.messages.count) {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.lastStreamingMessageID) {
                if let id = viewModel.lastStreamingMessageID {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Start a conversation")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Type a message below to begin working with the agent.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let lastID = viewModel.messages.last?.id else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }

    // MARK: - Actions

    private func retryMessage(_ message: ThreadMessage) {
        // Re-send the user message that preceded this agent response.
    }

    private func copyMessage(_ message: ThreadMessage) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        #endif
    }

    private func deleteMessage(_ message: ThreadMessage) {
        viewModel.messages.removeAll { $0.id == message.id }
    }
}

// MARK: - GateProgressView

/// Horizontal progress bar at the top showing gate status.
/// Three stages: Syntax Gate -> Repeat Gate -> Compilation Gate.
public struct GateProgressView: View {
    public let gates: [GateProgress]

    public init(gates: [GateProgress]) {
        self.gates = gates
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(gates.enumerated()), id: \.element.name) { index, gate in
                gateItem(gate)
                if index < gates.count - 1 {
                    connectorLine(
                        passed: gate.status == .passed
                    )
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func gateItem(_ gate: GateProgress) -> some View {
        HStack(spacing: 6) {
            gateIcon(for: gate.status)
            VStack(alignment: .leading, spacing: 1) {
                Text(gate.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                statusLabel(for: gate.status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func gateIcon(for status: GateProgress.GateStatus) -> some View {
        ZStack {
            Circle()
                .fill(statusColor(status).opacity(0.15))
                .frame(width: 24, height: 24)

            switch status {
            case .pending:
                Image(systemName: "circle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            case .running:
                ProgressView()
                    .controlSize(.small)
            case .passed:
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func statusLabel(for status: GateProgress.GateStatus) -> some View {
        switch status {
        case .pending:
            Text("Waiting")
        case .running:
            Text("Running...")
        case .passed:
            Text("Passed")
        case .failed(let error):
            Text(error.isEmpty ? "Failed" : error)
                .lineLimit(1)
        }
    }

    private func connectorLine(passed: Bool) -> some View {
        Rectangle()
            .fill(passed ? Color.green.opacity(0.4) : Color.secondary.opacity(0.15))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
    }

    private func statusColor(_ status: GateProgress.GateStatus) -> Color {
        switch status {
        case .pending: return .secondary
        case .running: return .blue
        case .passed: return .green
        case .failed: return .red
        }
    }
}

// MARK: - MessageBubbleView

/// Individual message bubble. Agent messages are left-aligned, user messages right-aligned.
public struct MessageBubbleView: View {
    public let message: ThreadMessage
    public let isHovered: Bool
    public let onRetry: () -> Void
    public let onCopy: () -> Void
    public let onDelete: () -> Void

    @State private var isThinkingExpanded = false

    public init(
        message: ThreadMessage,
        isHovered: Bool = false,
        onRetry: @escaping () -> Void = {},
        onCopy: @escaping () -> Void = {},
        onDelete: @escaping () -> Void = {}
    ) {
        self.message = message
        self.isHovered = isHovered
        self.onRetry = onRetry
        self.onCopy = onCopy
        self.onDelete = onDelete
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            if message.role == .agent {
                agentAvatar
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                messageHeader
                messageContent
                messageFooter
            }

            if message.role == .user {
                userAvatar
            }

            if message.role == .agent {
                Spacer(minLength: 60)
            }
        }
        .padding(.vertical, 6)
        .overlay(alignment: .topTrailing) {
            if isHovered {
                messageActions
                    .padding(4)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    // MARK: - Avatars

    @ViewBuilder
    private var agentAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 32, height: 32)
            Image(systemName: "brain.head.profile")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.accentColor)
        }
    }

    @ViewBuilder
    private var userAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.orange.opacity(0.15))
                .frame(width: 32, height: 32)
            Image(systemName: "person.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var messageHeader: some View {
        HStack(spacing: 6) {
            Text(roleLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if isHovered {
                Text(formattedTimestamp)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var roleLabel: String {
        switch message.role {
        case .user: return "You"
        case .agent: return "Agent"
        case .system: return "System"
        case .gateResult: return "Gate"
        }
    }

    private var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: message.timestamp)
    }

    // MARK: - Content

    @ViewBuilder
    private var messageContent: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            // Thinking section (collapsible)
            if let thinking = message.thinkingContent, !thinking.isEmpty {
                thinkingSection(thinking)
            }

            // Tool calls
            if !message.toolCalls.isEmpty {
                ForEach(message.toolCalls) { toolCall in
                    ToolExecutionIndicatorView(toolCall: toolCall)
                }
            }

            // Main message content with code blocks
            if !message.content.isEmpty {
                RichMessageView(
                    content: message.content,
                    isStreaming: message.isStreaming
                )
            }

            // Tool results
            if !message.toolResults.isEmpty {
                ForEach(message.toolResults) { result in
                    if !result.output.isEmpty {
                        toolResultSection(result)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(bubbleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }

    @ViewBuilder
    private func thinkingSection(_ thinking: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isThinkingExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "brain.head.profile")
                        .font(.caption)
                    Text("Thinking")
                        .font(.caption.weight(.medium))
                    Image(systemName: isThinkingExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if isThinkingExpanded {
                Text(thinking)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private func toolResultSection(_ result: ThreadToolResult) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: result.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(result.isError ? .red : .green)
                Text(result.isError ? "Error" : "Output")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(result.output)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        switch message.role {
        case .user:
            Color.accentColor.opacity(0.08)
        case .agent:
            Color(nsColor: .controlBackgroundColor)
        case .system:
            Color.orange.opacity(0.06)
        case .gateResult:
            Color.secondary.opacity(0.06)
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var messageFooter: some View {
        if message.isStreaming {
            streamingIndicator
        }
    }

    private var streamingIndicator: some View {
        HStack(spacing: 4) {
            StreamingCursorView()
            Text("Generating...")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Actions Overlay

    @ViewBuilder
    private var messageActions: some View {
        HStack(spacing: 2) {
            actionButton(icon: "doc.on.doc", label: "Copy", action: onCopy)
            if message.role == .agent {
                actionButton(icon: "arrow.clockwise", label: "Retry", action: onRetry)
            }
            actionButton(icon: "trash", label: "Delete", action: onDelete)
        }
        .padding(4)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.1), radius: 3)
    }

    @ViewBuilder
    private func actionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .help(label)
    }
}

// MARK: - RichMessageView

/// Parses message content and renders text, code blocks, and inline formatting.
public struct RichMessageView: View {
    public let content: String
    public let isStreaming: Bool

    @State private var copiedBlockID: String?

    public init(content: String, isStreaming: Bool = false) {
        self.content = content
        self.isStreaming = isStreaming
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parsedSegments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let text):
                    textSegment(text)
                case .codeBlock(let language, let code, let id):
                    CodeBlockView(
                        language: language,
                        code: code,
                        isCopied: copiedBlockID == id
                    ) {
                        copyToClipboard(code)
                        copiedBlockID = id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            if copiedBlockID == id { copiedBlockID = nil }
                        }
                    }
                }
            }

            if isStreaming {
                StreamingCursorView()
            }
        }
    }

    @ViewBuilder
    private func textSegment(_ text: String) -> some View {
        Text(LocalizedStringKey(text))
            .font(.body)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func copyToClipboard(_ text: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    // MARK: - Parsing

    private enum ContentSegment: Identifiable {
        case text(String)
        case codeBlock(language: String, code: String, id: String)

        var id: String {
            switch self {
            case .text(let t): return "text-\(t.hashValue)"
            case .codeBlock(_, _, let id): return id
            }
        }
    }

    private var parsedSegments: [ContentSegment] {
        var segments: [ContentSegment] = []
        let pattern = #"```(\w*)\n([\s\S]*?)```"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [.text(content)]
        }

        let nsContent = content as NSString
        var lastEnd = 0
        let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))

        for match in matches {
            // Text before code block
            if match.range.location > lastEnd {
                let textRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                let text = nsContent.substring(with: textRange).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    segments.append(.text(text))
                }
            }

            // Code block
            let langRange = match.range(at: 1)
            let codeRange = match.range(at: 2)
            let language = langRange.location != NSNotFound ? nsContent.substring(with: langRange) : ""
            let code = nsContent.substring(with: codeRange)
            segments.append(.codeBlock(
                language: language.isEmpty ? "code" : language,
                code: String(code.dropLast(while: { $0 == "\n" })),
                id: "block-\(match.range.location)"
            ))

            lastEnd = match.range.upperBound
        }

        // Trailing text
        if lastEnd < nsContent.length {
            let remaining = nsContent.substring(from: lastEnd).trimmingCharacters(in: .whitespacesAndNewlines)
            if !remaining.isEmpty {
                segments.append(.text(remaining))
            }
        }

        if segments.isEmpty {
            segments.append(.text(content))
        }

        return segments
    }
}

// MARK: - CodeBlockView

/// A syntax-highlighted code block with language label, line numbers, copy, and expand.
public struct CodeBlockView: View {
    public let language: String
    public let code: String
    public let isCopied: Bool
    public let onCopy: () -> Void

    @State private var isExpanded = true
    @State private var showFullCode = false

    private let maxCollapsedLines = 8

    public init(
        language: String,
        code: String,
        isCopied: Bool = false,
        onCopy: @escaping () -> Void = {}
    ) {
        self.language = language
        self.code = code
        self.isCopied = isCopied
        self.onCopy = onCopy
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            codeContent
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Header Bar

    @ViewBuilder
    private var headerBar: some View {
        HStack(spacing: 0) {
            // Language badge
            HStack(spacing: 4) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.caption2)
                Text(language.uppercased())
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.08))

            Spacer()

            // Line count
            let lineCount = code.components(separatedBy: "\n").count
            Text("\(lineCount) lines")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.trailing, 8)

            // Copy button
            Button(action: onCopy) {
                HStack(spacing: 3) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                    if isCopied {
                        Text("Copied")
                            .font(.caption2)
                    }
                }
                .foregroundStyle(isCopied ? .green : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)

            // Expand/collapse button
            if code.components(separatedBy: "\n").count > maxCollapsedLines {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "minus.square" : "plus.square")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .padding(0)
    }

    // MARK: - Code Content

    @ViewBuilder
    private var codeContent: some View {
        let lines = code.components(separatedBy: "\n")
        let displayLines = isExpanded ? lines : Array(lines.prefix(maxCollapsedLines))

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {
                // Line numbers
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(Array(displayLines.enumerated()), id: \.offset) { index, _ in
                        Text("\(index + 1)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary.opacity(0.6))
                            .frame(width: 30, alignment: .trailing)
                            .padding(.trailing, 8)
                    }
                }
                .padding(.leading, 10)
                .padding(.vertical, 10)

                // Divider
                Rectangle()
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 1)

                // Code
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(displayLines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.caption.monospaced())
                            .foregroundStyle(syntaxColor(for: line))
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.4))

        // Collapsed indicator
        if !isExpanded && lines.count > maxCollapsedLines {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.down")
                    Text("Show \(lines.count - maxCollapsedLines) more lines")
                }
                .font(.caption)
                .foregroundStyle(.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Basic Syntax Colors

    /// Lightweight keyword-aware coloring. Full Highlight.js/TreeSitter integration
    /// can replace this later.
    private func syntaxColor(for line: String) -> Color {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("//") || trimmed.hasPrefix("#") || trimmed.hasPrefix("/*") {
            return .secondary.opacity(0.7)
        }
        if trimmed.hasPrefix("func ") || trimmed.hasPrefix("let ") || trimmed.hasPrefix("var ")
            || trimmed.hasPrefix("class ") || trimmed.hasPrefix("struct ") || trimmed.hasPrefix("enum ")
            || trimmed.hasPrefix("import ") || trimmed.hasPrefix("public ") || trimmed.hasPrefix("private ")
            || trimmed.hasPrefix("if ") || trimmed.hasPrefix("else ") || trimmed.hasPrefix("return ")
            || trimmed.hasPrefix("for ") || trimmed.hasPrefix("while ") || trimmed.hasPrefix("switch ")
            || trimmed.hasPrefix("case ") || trimmed.hasPrefix("def ") || trimmed.hasPrefix("fn ")
            || trimmed.hasPrefix("pub ") || trimmed.hasPrefix("use ") || trimmed.hasPrefix("mod ")
        {
            return .purple
        }
        if trimmed.hasPrefix("\"") || trimmed.hasPrefix("'") || trimmed.hasPrefix("`") {
            return .green
        }
        return .primary
    }
}

// MARK: - ToolExecutionIndicatorView

/// Inline indicator for tool execution status.
/// Shows: icon, tool name, status, and expandable arguments.
public struct ToolExecutionIndicatorView: View {
    public let toolCall: ThreadToolCall

    @State private var isExpanded = false

    public init(toolCall: ThreadToolCall) {
        self.toolCall = toolCall
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    statusIcon
                    toolNameLabel
                    Spacer()
                    statusLabel
                    if !toolCall.arguments.isEmpty {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(toolBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            if isExpanded && !toolCall.arguments.isEmpty {
                expandedArguments
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch toolCall.status {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .running:
            ProgressView()
                .controlSize(.mini)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private var toolNameLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: toolIconName)
                .font(.caption2)
            Text(toolCall.name)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
        }
    }

    private var statusLabel: some View {
        switch toolCall.status {
        case .pending:
            Text("Pending")
                .foregroundStyle(.secondary)
        case .running:
            Text("Running \(toolCall.name)...")
                .foregroundStyle(.blue)
        case .succeeded(let output):
            Text("Done")
                .foregroundStyle(.green)
        case .failed(let error):
            Text(error.isEmpty ? "Failed" : error)
                .foregroundStyle(.red)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var expandedArguments: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(toolCall.arguments)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var toolBackground: some View {
        switch toolCall.status {
        case .running:
            Color.blue.opacity(0.06)
        case .succeeded:
            Color.green.opacity(0.04)
        case .failed:
            Color.red.opacity(0.04)
        case .pending:
            Color.secondary.opacity(0.04)
        }
    }

    private var toolIconName: String {
        switch toolCall.name {
        case "bash", "shell": return "terminal"
        case "file", "write": return "doc.text"
        case "read": return "doc"
        case "grep": return "magnifyingglass"
        case "glob": return "folder"
        case "edit": return "pencil.and.list.clipboard"
        default: return "wrench.and.screwdriver"
        }
    }
}

// MARK: - MessageInputBar

/// Bottom input bar: text editor, attachment button, model selector, and send button.
public struct MessageInputBar: View {
    @Binding public var text: String
    @Binding public var selectedModel: String
    public let availableModels: [String]
    public let isGenerating: Bool
    public let onSend: () -> Void
    public let onClear: () -> Void

    @FocusState private var isInputFocused: Bool
    @State private var showingModelPicker = false
    @State private var hoverSend = false

    public init(
        text: Binding<String>,
        selectedModel: Binding<String>,
        availableModels: [String] = ["gpt-4o"],
        isGenerating: Bool = false,
        onSend: @escaping () -> Void = {},
        onClear: @escaping () -> Void = {}
    ) {
        self._text = text
        self._selectedModel = selectedModel
        self.availableModels = availableModels
        self.isGenerating = isGenerating
        self.onSend = onSend
        self.onClear = onClear
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 10) {
                // Attachment button
                Button(action: {}) {
                    Image(systemName: "paperclip")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .help("Attach file")

                // Model selector
                modelSelector

                // Text input
                textEditor

                // Send / stop button
                sendButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            inputHints
        }
        .background(.ultraThinMaterial)
        .onAppear { isInputFocused = true }
    }

    // MARK: - Model Selector

    @ViewBuilder
    private var modelSelector: some View {
        Menu {
            ForEach(availableModels, id: \.self) { model in
                Button {
                    selectedModel = model
                } label: {
                    HStack {
                        Text(model)
                        if model == selectedModel {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedModel)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Text Editor

    @ViewBuilder
    private var textEditor: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("Message the agent...")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 8)
            }

            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
                .focused($isInputFocused)
                .onSubmit {
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onSend()
                    }
                }
        }
        .frame(minHeight: 36, maxHeight: 120)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isInputFocused ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.12),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Send Button

    @ViewBuilder
    private var sendButton: some View {
        Button(action: {
            if isGenerating {
                // Stop generation
            } else {
                onSend()
            }
        }) {
            Image(systemName: isGenerating ? "stop.fill" : "arrow.up")
                .font(.body.weight(.semibold))
                .foregroundStyle(sendButtonForeground)
                .frame(width: 32, height: 32)
                .background(sendButtonBackground)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isGenerating && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity(canSend || isGenerating ? 1.0 : 0.4)
        .onHover { hoverSend = $0 }
        .help(isGenerating ? "Stop generating" : "Send message (Return)")
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sendButtonForeground: Color {
        if isGenerating { return .white }
        return (canSend || hoverSend) ? .white : .secondary
    }

    private var sendButtonBackground: Color {
        if isGenerating { return .red }
        return (canSend || hoverSend) ? Color.accentColor : Color.secondary.opacity(0.2)
    }

    // MARK: - Hints

    @ViewBuilder
    private var inputHints: some View {
        HStack(spacing: 12) {
            Text("Return to send")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text("Shift+Return for newline")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            if !text.isEmpty {
                Text("\(text.count) chars")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }
}

// MARK: - StreamingCursorView

/// Blinking cursor animation shown during streaming text.
public struct StreamingCursorView: View {
    @State private var opacity: Double = 1.0

    public init() {}

    public var body: some View {
        Text("\u{258C}")
            .font(.body.monospaced())
            .foregroundStyle(Color.accentColor)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    opacity = 0.0
                }
            }
    }
}

// MARK: - LoadingSkeletonView

/// Placeholder skeleton UI while waiting for the first response.
public struct LoadingSkeletonView: View {
    @State private var shimmerOffset: CGFloat = -200

    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { index in
                skeletonRow(alignment: index % 2 == 0 ? .leading : .trailing)
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                shimmerOffset = 400
            }
        }
    }

    @ViewBuilder
    private func skeletonRow(alignment: HorizontalAlignment) -> some View {
        HStack {
            if alignment == .trailing { Spacer(minLength: 80) }

            VStack(alignment: alignment, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: 80, height: 10)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: 200, height: 10)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: 140, height: 10)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if alignment == .leading { Spacer(minLength: 80) }
        }
    }
}

// MARK: - Preview

#Preview("Thread View") {
    ThreadView()
        .frame(width: 700, height: 600)
}
