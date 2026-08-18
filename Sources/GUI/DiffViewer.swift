// TUI - DiffViewer
// Side-by-side and unified diff viewer for reviewing agent code changes
// Inspired by Codex app's diff review in threads

import SwiftUI

// MARK: - Diff Line Model

/// Represents a single line in a diff, with its type, content, and line numbers.
public struct DiffLine: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let type: DiffLineType
    public let content: String
    public let oldLineNum: Int?
    public let newLineNum: Int?

    public init(
        id: UUID = UUID(),
        type: DiffLineType,
        content: String,
        oldLineNum: Int? = nil,
        newLineNum: Int? = nil
    ) {
        self.id = id
        self.type = type
        self.content = content
        self.oldLineNum = oldLineNum
        self.newLineNum = newLineNum
    }
}

/// The type of a diff line: addition, deletion, modification, or context.
public enum DiffLineType: String, Sendable, CaseIterable {
    case addition
    case deletion
    case modification
    case context
    case header
    case hunkHeader

    /// Background color for this line type.
    public var backgroundColor: String {
        switch self {
        case .addition: return "diffAddition"
        case .deletion: return "diffDeletion"
        case .modification: return "diffModification"
        case .context: return "diffContext"
        case .header, .hunkHeader: return "diffHeader"
        }
    }

    /// Prefix indicator for unified diff view.
    public var prefix: String {
        switch self {
        case .addition: return "+"
        case .deletion: return "-"
        case .modification: return "~"
        case .context: return " "
        case .header: return "#"
        case .hunkHeader: return "@"
        }
    }
}

// MARK: - Diff Hunk Model

/// A group of related diff lines representing a contiguous change region.
public struct DiffHunk: Sendable, Identifiable {
    public let id: UUID
    public let header: String
    public let oldStart: Int
    public let oldCount: Int
    public let newStart: Int
    public let newCount: Int
    public var lines: [DiffLine]
    public var isExpanded: Bool

    public init(
        id: UUID = UUID(),
        header: String,
        oldStart: Int,
        oldCount: Int,
        newStart: Int,
        newCount: Int,
        lines: [DiffLine],
        isExpanded: Bool = true
    ) {
        self.id = id
        self.header = header
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.lines = lines
        self.isExpanded = isExpanded
    }

    /// Number of added lines in this hunk.
    public var additions: Int {
        lines.filter { $0.type == .addition }.count
    }

    /// Number of deleted lines in this hunk.
    public var deletions: Int {
        lines.filter { $0.type == .deletion }.count
    }
}

// MARK: - Diff File Model

/// Represents a complete file diff with hunks and metadata.
public struct DiffFile: Sendable, Identifiable {
    public let id: UUID
    public let filePath: String
    public let language: DiffLanguage
    public var hunks: [DiffHunk]
    public var isExpanded: Bool

    public init(
        id: UUID = UUID(),
        filePath: String,
        language: DiffLanguage = .unknown,
        hunks: [DiffHunk],
        isExpanded: Bool = true
    ) {
        self.id = id
        self.filePath = filePath
        self.language = language
        self.hunks = hunks
        self.isExpanded = isExpanded
    }

    /// Total additions across all hunks.
    public var additions: Int {
        hunks.reduce(0) { $0 + $1.additions }
    }

    /// Total deletions across all hunks.
    public var deletions: Int {
        hunks.reduce(0) { $0 + $1.deletions }
    }

    /// Filename extracted from the full path.
    public var fileName: String {
        (filePath as NSString).lastPathComponent
    }

    /// Directory path extracted from the full path.
    public var directoryPath: String {
        (filePath as NSString).deletingLastPathComponent
    }
}

// MARK: - Diff Language

/// Supported programming languages for syntax highlighting.
public enum DiffLanguage: String, Sendable, CaseIterable {
    case swift
    case python
    case typescript
    case javascript
    case rust
    case go
    case java
    case ruby
    case cpp
    case c
    case html
    case css
    case json
    case yaml
    case markdown
    case shell
    case unknown

    /// Detect language from file extension.
    public static func detect(from filename: String) -> DiffLanguage {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return .swift
        case "py", "pyw": return .python
        case "ts", "tsx": return .typescript
        case "js", "jsx", "mjs": return .javascript
        case "rs": return .rust
        case "go": return .go
        case "java": return .java
        case "rb": return .ruby
        case "cpp", "cc", "cxx", "hpp": return .cpp
        case "c", "h": return .c
        case "html", "htm": return .html
        case "css", "scss": return .css
        case "json": return .json
        case "yaml", "yml": return .yaml
        case "md", "markdown": return .markdown
        case "sh", "bash", "zsh": return .shell
        default: return .unknown
        }
    }

    /// Language icon for the file header.
    public var icon: String {
        switch self {
        case .swift: return "🐦"
        case .python: return "🐍"
        case .typescript: return "🔷"
        case .javascript: return "🟨"
        case .rust: return "🦀"
        case .go: return "🐹"
        case .java: return "☕"
        case .ruby: return "💎"
        case .cpp, .c: return "⚙️"
        case .html: return "🌐"
        case .css: return "🎨"
        case .json: return "📋"
        case .yaml: return "📄"
        case .markdown: return "📝"
        case .shell: return "🐚"
        case .unknown: return "📄"
        }
    }
}

// MARK: - Diff Stats Model

/// Aggregated statistics for a set of file diffs.
public struct DiffStats: Sendable {
    public let filesChanged: Int
    public let insertions: Int
    public let deletions: Int

    public init(filesChanged: Int, insertions: Int, deletions: Int) {
        self.filesChanged = filesChanged
        self.insertions = insertions
        self.deletions = deletions
    }

    /// Human-readable summary string.
    public var summary: String {
        var parts: [String] = []
        if filesChanged > 0 {
            parts.append("\(filesChanged) file\(filesChanged == 1 ? "" : "s") changed")
        }
        if insertions > 0 {
            parts.append("\(insertions) insertion\(insertions == 1 ? "" : "s")(+)")
        }
        if deletions > 0 {
            parts.append("\(deletions) deletion\(deletions == 1 ? "" : "s")(-)")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Diff Viewer View Mode

/// The display mode for the diff viewer.
public enum DiffViewMode: String, Sendable, CaseIterable {
    case sideBySide = "Side by Side"
    case unified = "Unified"
}

// MARK: - Diff Viewer State

/// Observable state manager for the diff viewer.
@Observable
public final class DiffViewerState: Sendable {
    /// The files being displayed.
    public var files: [DiffFile]

    /// Current view mode.
    public var viewMode: DiffViewMode

    /// Index of the currently focused change.
    public var currentChangeIndex: Int

    /// Search query for filtering lines.
    public var searchQuery: String

    /// Whether search is active.
    public var isSearchActive: Bool

    /// Currently focused file index.
    public var focusedFileIndex: Int

    /// Number of context lines to show around changes.
    public var contextLineCount: Int

    /// Actions to perform when applying/discarding hunks.
    public var onApply: ((DiffHunk) -> Void)?
    public var onDiscard: ((DiffHunk) -> Void)?

    public init(
        files: [DiffFile] = [],
        viewMode: DiffViewMode = .sideBySide,
        currentChangeIndex: Int = 0,
        searchQuery: String = "",
        isSearchActive: Bool = false,
        focusedFileIndex: Int = 0,
        contextLineCount: Int = 3,
        onApply: ((DiffHunk) -> Void)? = nil,
        onDiscard: ((DiffHunk) -> Void)? = nil
    ) {
        self.files = files
        self.viewMode = viewMode
        self.currentChangeIndex = currentChangeIndex
        self.searchQuery = searchQuery
        self.isSearchActive = isSearchActive
        self.focusedFileIndex = focusedFileIndex
        self.contextLineCount = contextLineCount
        self.onApply = onApply
        self.onDiscard = onDiscard
    }

    /// Aggregated stats across all files.
    public var stats: DiffStats {
        DiffStats(
            filesChanged: files.count,
            insertions: files.reduce(0) { $0 + $1.additions },
            deletions: files.reduce(0) { $0 + $1.deletions }
        )
    }

    /// Total number of changes across all files.
    public var totalChanges: Int {
        files.reduce(0) { fileAcc, file in
            fileAcc + file.hunks.reduce(0) { hunkAcc, hunk in
                hunkAcc + hunk.additions + hunk.deletions
            }
        }
    }

    /// All hunks across all files in order.
    public var allHunks: [DiffHunk] {
        files.flatMap(\.hunks)
    }

    /// Navigate to the next change.
    public func nextChange() {
        guard currentChangeIndex < totalChanges - 1 else { return }
        currentChangeIndex += 1
    }

    /// Navigate to the previous change.
    public func previousChange() {
        guard currentChangeIndex > 0 else { return }
        currentChangeIndex -= 1
    }

    /// Toggle expand/collapse for a file.
    public func toggleFileExpansion(_ fileId: UUID) {
        if let index = files.firstIndex(where: { $0.id == fileId }) {
            files[index].isExpanded.toggle()
        }
    }

    /// Toggle expand/collapse for a hunk.
    public func toggleHunkExpansion(_ hunkId: UUID) {
        for fileIndex in files.indices {
            if let hunkIndex = files[fileIndex].hunks.firstIndex(where: { $0.id == hunkId }) {
                files[fileIndex].hunks[hunkIndex].isExpanded.toggle()
            }
        }
    }

    /// Apply a specific hunk.
    public func applyHunk(_ hunk: DiffHunk) {
        onApply?(hunk)
    }

    /// Discard a specific hunk.
    public func discardHunk(_ hunk: DiffHunk) {
        onDiscard?(hunk)
    }
}

// MARK: - Diff Viewer View

/// The main diff viewer component with side-by-side and unified views.
public struct DiffViewer: View {
    @Bindable public var state: DiffViewerState
    @FocusState private var isSearchFieldFocused: Bool

    public init(state: DiffViewerState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Summary bar
            DiffStatsView(stats: state.stats)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)

            // Toolbar with view mode toggle and controls
            toolbarView
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            Divider()

            // Main diff content
            ScrollView([.horizontal, .vertical]) {
                if state.viewMode == .sideBySide {
                    SideBySideView(state: state)
                } else {
                    UnifiedDiffView(state: state)
                }
            }
            .coordinateSpace(name: "diffScrollView")

            Divider()

            // Navigation footer
            navigationFooter
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
        }
        .background(.background)
    }

    // MARK: - Toolbar

    private var toolbarView: some View {
        HStack(spacing: 12) {
            // View mode segmented control
            Picker("View Mode", selection: $state.viewMode) {
                ForEach(DiffViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)

            Spacer()

            // Navigation controls
            HStack(spacing: 8) {
                Button(action: { state.previousChange() }) {
                    Label("Previous", systemImage: "chevron.up")
                }
                .keyboardShortcut("k", modifiers: [])
                .disabled(state.currentChangeIndex <= 0)

                Text("\(state.currentChangeIndex + 1)/\(state.totalChanges)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button(action: { state.nextChange() }) {
                    Label("Next", systemImage: "chevron.down")
                }
                .keyboardShortcut("j", modifiers: [])
                .disabled(state.currentChangeIndex >= state.totalChanges - 1)
            }

            Divider()
                .frame(height: 20)

            // Context lines control
            HStack(spacing: 4) {
                Text("Context:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("-") {
                    state.contextLineCount = max(0, state.contextLineCount - 1)
                }
                .buttonStyle(.borderless)
                Text("\(state.contextLineCount)")
                    .font(.caption.monospacedDigit())
                    .frame(width: 20)
                Button("+") {
                    state.contextLineCount = min(10, state.contextLineCount + 1)
                }
                .buttonStyle(.borderless)
            }

            Divider()
                .frame(height: 20)

            // Search toggle
            Button(action: { state.isSearchActive.toggle() }) {
                Label("Search", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("f", modifiers: .command)
        }
    }

    // MARK: - Navigation Footer

    private var navigationFooter: some View {
        HStack {
            if state.isSearchActive {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search in diff...", text: $state.searchQuery)
                        .textFieldStyle(.plain)
                        .focused($isSearchFieldFocused)
                    if !state.searchQuery.isEmpty {
                        Button(action: { state.searchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(6)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .frame(maxWidth: 300)
            }

            Spacer()

            // File count indicator
            Text("\(state.files.count) file\(state.files.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Diff Stats View

/// Displays a summary bar of diff statistics.
public struct DiffStatsView: View {
    let stats: DiffStats

    public init(stats: DiffStats) {
        self.stats = stats
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(.secondary)

            Text(stats.summary)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()

            // Visual stats
            HStack(spacing: 8) {
                if stats.insertions > 0 {
                    Label("\(stats.insertions)", systemImage: "plus.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption.monospacedDigit())
                }
                if stats.deletions > 0 {
                    Label("\(stats.deletions)", systemImage: "minus.circle.fill")
                        .foregroundStyle(.red)
                        .font(.caption.monospacedDigit())
                }
            }
        }
    }
}

// MARK: - Side by Side View

/// Displays diffs in a two-column layout with original on left and modified on right.
public struct SideBySideView: View {
    @Bindable var state: DiffViewerState

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(state.files) { file in
                DiffFileHeader(file: file, state: state)

                if file.isExpanded {
                    ForEach(file.hunks) { hunk in
                        if hunk.isExpanded {
                            SideBySideHunkView(
                                hunk: hunk,
                                searchQuery: state.searchQuery,
                                contextLineCount: state.contextLineCount
                            )
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Side by Side Hunk View

/// A single hunk displayed in side-by-side mode.
struct SideBySideHunkView: View {
    let hunk: DiffHunk
    let searchQuery: String
    let contextLineCount: Int

    private var pairedLines: [(left: DiffLine?, right: DiffLine?)] {
        var result: [(left: DiffLine?, right: DiffLine?)] = []
        var i = 0

        while i < hunk.lines.count {
            let line = hunk.lines[i]

            switch line.type {
            case .addition:
                // Find matching deletion if exists
                result.append((left: nil, right: line))

            case .deletion:
                // Check if next line is an addition (modification)
                if i + 1 < hunk.lines.count && hunk.lines[i + 1].type == .addition {
                    result.append((left: line, right: hunk.lines[i + 1]))
                    i += 1
                } else {
                    result.append((left: line, right: nil))
                }

            case .context:
                result.append((left: line, right: line))

            case .modification:
                result.append((left: line, right: line))

            default:
                break
            }

            i += 1
        }

        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Hunk header
            HStack {
                Text(hunk.header)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("+\(hunk.additions)/-\(hunk.deletions)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.5))

            // Paired lines
            ForEach(Array(pairedLines.enumerated()), id: \.offset) { index, pair in
                SideBySideLinePair(
                    left: pair.left,
                    right: pair.right,
                    searchQuery: searchQuery
                )
            }
        }
    }
}

// MARK: - Side by Side Line Pair

/// A pair of lines (left/right) in side-by-side view.
struct SideBySideLinePair: View {
    let left: DiffLine?
    let right: DiffLine?
    let searchQuery: String

    var body: some View {
        HStack(spacing: 0) {
            // Left panel (original)
            DiffLineView(
                line: left,
                side: .left,
                searchQuery: searchQuery
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            // Divider
            Divider()
                .frame(width: 1)

            // Right panel (modified)
            DiffLineView(
                line: right,
                side: .right,
                searchQuery: searchQuery
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: lineHeight)
    }

    private var lineHeight: CGFloat {
        let content = right?.content ?? left?.content ?? ""
        let lineCount = content.components(separatedBy: "\n").count
        return max(20, CGFloat(lineCount) * 16)
    }
}

// MARK: - Unified Diff View

/// Displays diffs in a single column with +/- indicators.
public struct UnifiedDiffView: View {
    @Bindable var state: DiffViewerState

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(state.files) { file in
                DiffFileHeader(file: file, state: state)

                if file.isExpanded {
                    ForEach(file.hunks) { hunk in
                        if hunk.isExpanded {
                            UnifiedHunkView(
                                hunk: hunk,
                                searchQuery: state.searchQuery
                            )
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Unified Hunk View

/// A single hunk displayed in unified mode.
struct UnifiedHunkView: View {
    let hunk: DiffHunk
    let searchQuery: String

    var body: some View {
        VStack(spacing: 0) {
            // Hunk header
            HStack {
                Text(hunk.header)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("+\(hunk.additions)/-\(hunk.deletions)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.5))

            // Lines
            ForEach(hunk.lines) { line in
                DiffLineView(
                    line: line,
                    side: .unified,
                    searchQuery: searchQuery
                )
            }
        }
    }
}

// MARK: - Diff Line View

/// A single line in the diff, with line numbers and syntax highlighting.
public struct DiffLineView: View {
    let line: DiffLine?
    let side: DiffLineSide
    let searchQuery: String

    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        HStack(spacing: 0) {
            if let line = line {
                // Line number
                Text(lineNumberText(line))
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .frame(width: 50, alignment: .trailing)
                    .padding(.trailing, 8)

                // Prefix indicator (unified view only)
                if side == .unified {
                    Text(line.type.prefix)
                        .font(.caption.monospaced())
                        .foregroundStyle(prefixColor(line.type))
                        .frame(width: 16, alignment: .center)
                }

                // Code content
                Text(attributedContent(line))
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            } else {
                // Empty placeholder
                Text("")
                    .font(.body.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            }
        }
        .background(backgroundColor(line))
        .overlay(alignment: .leading) {
            if let line = line, line.type != .context && line.type != .hunkHeader {
                Rectangle()
                    .fill(prefixColor(line.type))
                    .frame(width: 3)
            }
        }
    }

    // MARK: - Helpers

    private func lineNumberText(_ line: DiffLine) -> String {
        switch side {
        case .left:
            return line.oldLineNum.map(String.init) ?? ""
        case .right:
            return line.newLineNum.map(String.init) ?? ""
        case .unified:
            if let old = line.oldLineNum, let new = line.newLineNum {
                return "\(old)"
            } else if let old = line.oldLineNum {
                return "\(old)"
            } else if let new = line.newLineNum {
                return "\(new)"
            }
            return ""
        }
    }

    private func backgroundColor(_ line: DiffLine?) -> Color {
        guard let line = line else { return .clear }

        let isSearchMatch = !searchQuery.isEmpty &&
            line.content.localizedCaseInsensitiveContains(searchQuery)

        if isSearchMatch {
            return .yellow.opacity(0.3)
        }

        switch line.type {
        case .addition:
            return .green.opacity(0.15)
        case .deletion:
            return .red.opacity(0.15)
        case .modification:
            return .yellow.opacity(0.15)
        case .context:
            return .clear
        case .header, .hunkHeader:
            return .blue.opacity(0.1)
        }
    }

    private func prefixColor(_ type: DiffLineType) -> Color {
        switch type {
        case .addition:
            return .green
        case .deletion:
            return .red
        case .modification:
            return .yellow
        case .context:
            return .clear
        case .header, .hunkHeader:
            return .blue
        }
    }

    private func attributedContent(_ line: DiffLine) -> AttributedString {
        var result = AttributedString(line.content)

        // Apply syntax highlighting
        if let highlight = syntaxHighlight(line.content, type: line.type) {
            result = highlight
        }

        return result
    }

    // MARK: - Basic Syntax Highlighting

    private func syntaxHighlight(_ content: String, type: DiffLineType) -> AttributedString? {
        guard type != .header && type != .hunkHeader else { return nil }

        var result = AttributedString(content)

        // Keywords pattern (simplified for performance)
        let keywords: Set<String> = [
            "func", "let", "var", "if", "else", "for", "while", "return",
            "import", "class", "struct", "enum", "protocol", "extension",
            "public", "private", "internal", "static", "mutating",
            "async", "await", "throws", "try", "catch",
            "def", "self", "None", "True", "False", "lambda", "with",
            "function", "const", "export", "default", "new", "this",
            "type", "interface", "abstract", "implements", "extends",
        ]

        // Highlight keywords
        for keyword in keywords {
            let pattern = "\\b\(keyword)\\b"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(content.startIndex..., in: content)
                for match in regex.matches(in: content, range: range) {
                    if let swiftRange = Range(match.range, in: result) {
                        result[swiftRange].foregroundColor = .purple
                    }
                }
            }
        }

        // Highlight strings
        let stringPattern = "\"[^\"]*\"|'[^']*'"
        if let regex = try? NSRegularExpression(pattern: stringPattern) {
            let range = NSRange(content.startIndex..., in: content)
            for match in regex.matches(in: content, range: range) {
                if let swiftRange = Range(match.range, in: result) {
                    result[swiftRange].foregroundColor = .green
                }
            }
        }

        // Highlight comments
        let commentPattern = "//.*$|/\\*.*\\*/|#.*$"
        if let regex = try? NSRegularExpression(pattern: commentPattern, options: .anchorsMatchLines) {
            let range = NSRange(content.startIndex..., in: content)
            for match in regex.matches(in: content, range: range) {
                if let swiftRange = Range(match.range, in: result) {
                    result[swiftRange].foregroundColor = .gray
                }
            }
        }

        // Highlight numbers
        let numberPattern = "\\b\\d+\\.?\\d*\\b"
        if let regex = try? NSRegularExpression(pattern: numberPattern) {
            let range = NSRange(content.startIndex..., in: content)
            for match in regex.matches(in: content, range: range) {
                if let swiftRange = Range(match.range, in: result) {
                    result[swiftRange].foregroundColor = .orange
                }
            }
        }

        return result
    }
}

// MARK: - Diff Line Side

/// Which side of the diff a line is on.
public enum DiffLineSide: Sendable {
    case left
    case right
    case unified
}

// MARK: - Diff File Header

/// The header row for a file diff, with filename, language icon, and stats.
struct DiffFileHeader: View {
    let file: DiffFile
    @Bindable var state: DiffViewerState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                // Expand/collapse button
                Button(action: { state.toggleFileExpansion(file.id) }) {
                    Image(systemName: file.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)

                // Language icon
                Text(file.language.icon)
                    .font(.title3)

                // File path
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.fileName)
                        .font(.headline)
                        .textSelection(.enabled)
                    if !file.directoryPath.isEmpty {
                        Text(file.directoryPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Spacer()

                // Change stats
                HStack(spacing: 8) {
                    if file.additions > 0 {
                        Text("+\(file.additions)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                    }
                    if file.deletions > 0 {
                        Text("-\(file.deletions)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.red)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.red.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

// MARK: - Preview Provider

#if DEBUG
struct DiffViewer_Previews: PreviewProvider {
    static var previews: some View {
        let sampleFiles = [
            DiffFile(
                filePath: "Sources/AdventurersCore/AgentLoop.swift",
                language: .swift,
                hunks: [
                    DiffHunk(
                        header: "@@ -10,8 +10,12 @@ public actor AgentLoop {",
                        oldStart: 10,
                        oldCount: 8,
                        newStart: 10,
                        newCount: 12,
                        lines: [
                            DiffLine(type: .context, content: "    private let config: HarnessConfig", oldLineNum: 10, newLineNum: 10),
                            DiffLine(type: .context, content: "    private let provider: LLMProvider", oldLineNum: 11, newLineNum: 11),
                            DiffLine(type: .deletion, content: "    private let gates: [Gate]", oldLineNum: 12, newLineNum: nil),
                            DiffLine(type: .addition, content: "    private var gates: [Gate]", oldLineNum: nil, newLineNum: 12),
                            DiffLine(type: .context, content: "    private let tools: [String: Tool]", oldLineNum: 13, newLineNum: 13),
                            DiffLine(type: .addition, content: "    private let maxRetries: Int", oldLineNum: nil, newLineNum: 14),
                            DiffLine(type: .context, content: "", oldLineNum: 14, newLineNum: 15),
                        ]
                    )
                ]
            ),
            DiffFile(
                filePath: "Tests/AgentLoopTests.swift",
                language: .swift,
                hunks: [
                    DiffHunk(
                        header: "@@ -5,3 +5,7 @@ import Testing",
                        oldStart: 5,
                        oldCount: 3,
                        newStart: 5,
                        newCount: 7,
                        lines: [
                            DiffLine(type: .context, content: "import Testing", oldLineNum: 5, newLineNum: 5),
                            DiffLine(type: .addition, content: "import AdventurersCore", oldLineNum: nil, newLineNum: 6),
                            DiffLine(type: .context, content: "", oldLineNum: 6, newLineNum: 7),
                            DiffLine(type: .addition, content: "@Test func testAgentLoop() async throws {", oldLineNum: nil, newLineNum: 8),
                            DiffLine(type: .addition, content: "    // TODO: Implement test", oldLineNum: nil, newLineNum: 9),
                            DiffLine(type: .addition, content: "}", oldLineNum: nil, newLineNum: 10),
                        ]
                    )
                ]
            )
        ]

        let state = DiffViewerState(files: sampleFiles)

        return DiffViewer(state: state)
            .frame(width: 900, height: 600)
    }
}
#endif
