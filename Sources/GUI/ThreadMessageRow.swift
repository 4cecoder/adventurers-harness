// ThreadMessageRow.swift
// Adventurers Harness — Message Bubble, Markdown/Code Renderers, Thinking Disclosure, and Action Overlays

import SwiftUI
import AdventurersCore

#if os(macOS)
import AppKit
#endif

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
                .fill(Color.white.opacity(0.08))
                .frame(width: 30, height: 30)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                )
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.9))
        }
    }

    @ViewBuilder
    private var userAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 30, height: 30)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
                )
            Image(systemName: "person.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
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

            // Multi-Tool execution cluster (auto-collapsing for multiple tools / large output)
            if !message.toolCalls.isEmpty || !message.toolResults.isEmpty {
                MultiToolCallClusterView(
                    toolCalls: message.toolCalls,
                    toolResults: message.toolResults
                )
            }

            // Main message content with code blocks
            if !message.content.isEmpty {
                RichMessageView(
                    content: message.content,
                    isStreaming: message.isStreaming
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            Group {
                if message.role == .user {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.adOrange.opacity(0.24),
                                    Color.adOrange.opacity(0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        stops: [
                                            .init(color: Color.white.opacity(0.35), location: 0.0),
                                            .init(color: Color.adOrange.opacity(0.25), location: 0.5),
                                            .init(color: Color.white.opacity(0.10), location: 1.0)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: Color.adOrange.opacity(0.20), radius: 10, x: 0, y: 3)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.04),
                                            Color.black.opacity(0.35)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        stops: [
                                            .init(color: Color.white.opacity(0.22), location: 0.0),
                                            .init(color: Color.white.opacity(0.04), location: 0.6),
                                            .init(color: Color.white.opacity(0.10), location: 1.0)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 4)
                }
            }
        )
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
                    Text("Thinking Process")
                        .font(.caption.weight(.medium))
                    Image(systemName: isThinkingExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(Color.adOrange)
            }
            .buttonStyle(.plain)

            if isThinkingExpanded {
                Text(thinking)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.adTextSecondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            }
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
        Text(LocalizedStringKey(sanitizedMarkdown(text)))
            .font(.body)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func sanitizedMarkdown(_ text: String) -> String {
        // Prevent broken SwiftUI rendering when raw tool output or path brackets are unbalanced
        var cleaned = text
        // Ensure double newlines around markdown headers so SwiftUI renders them properly
        let headerRegex = try? NSRegularExpression(pattern: "(?m)^(#+\\s+.*)$", options: [])
        if let headerRegex {
            cleaned = headerRegex.stringByReplacingMatches(in: cleaned, options: [], range: NSRange(location: 0, length: (cleaned as NSString).length), withTemplate: "\n$1\n")
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
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
        // Robust pattern matching both closed code blocks and open/streaming code blocks
        let pattern = #"(?ms)(?:^|\n)[ \t]*```([^\n\r]*)\r?\n([\s\S]*?)(?:(?:\r?\n[ \t]*```)|\z)"#

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
            var rawLang = langRange.location != NSNotFound ? nsContent.substring(with: langRange).trimmingCharacters(in: .whitespacesAndNewlines) : ""
            // Extract pure language token if metadata/filename is present (e.g. `swift title="Foo.swift"`)
            if let firstToken = rawLang.components(separatedBy: .whitespaces).first {
                rawLang = firstToken
            }
            let code = nsContent.substring(with: codeRange)
            let trimmedCode = code.trimmingCharacters(in: .newlines)

            if !trimmedCode.isEmpty || matches.count == 1 {
                segments.append(.codeBlock(
                    language: rawLang.isEmpty ? "code" : rawLang,
                    code: trimmedCode,
                    id: "block-\(match.range.location)"
                ))
            }

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
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Basic Syntax Colors

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
