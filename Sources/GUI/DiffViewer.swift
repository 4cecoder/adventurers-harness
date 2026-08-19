// GUI - DiffViewer
// Professional Full-Width Side-by-Side and Unified Diff Workbench
// Designed for high-clarity code review without nested sidebar clutter

import SwiftUI

// MARK: - Diff Line Model

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

public enum DiffLineType: String, Sendable, CaseIterable {
    case addition
    case deletion
    case modification
    case context
    case header
    case hunkHeader

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

    public var additions: Int {
        lines.filter { $0.type == .addition }.count
    }

    public var deletions: Int {
        lines.filter { $0.type == .deletion }.count
    }
}

// MARK: - Diff File Model

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
        self.language = language == .unknown ? DiffLanguage.detect(from: filePath) : language
        self.hunks = hunks
        self.isExpanded = isExpanded
    }

    public var additions: Int {
        hunks.reduce(0) { $0 + $1.additions }
    }

    public var deletions: Int {
        hunks.reduce(0) { $0 + $1.deletions }
    }

    public var fileName: String {
        (filePath as NSString).lastPathComponent
    }

    public var directoryPath: String {
        let dir = (filePath as NSString).deletingLastPathComponent
        return dir.isEmpty ? "." : dir
    }
}

// MARK: - Diff Language

public enum DiffLanguage: String, Sendable, CaseIterable {
    case swift
    case python
    case typescript
    case javascript
    case rust
    case go
    case json
    case yaml
    case markdown
    case shell
    case unknown

    public static func detect(from filename: String) -> DiffLanguage {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return .swift
        case "py": return .python
        case "ts", "tsx": return .typescript
        case "js", "jsx": return .javascript
        case "rs": return .rust
        case "go": return .go
        case "json": return .json
        case "yaml", "yml": return .yaml
        case "md": return .markdown
        case "sh", "zsh", "bash": return .shell
        default: return .unknown
        }
    }

    public var icon: String {
        switch self {
        case .swift: return "swift"
        case .python: return "chevron.left.forwardslash.chevron.right"
        case .typescript, .javascript: return "curlybraces"
        case .rust: return "gearshape.2"
        case .go: return "shippingbox"
        case .json, .yaml: return "ellipsis.curlybraces"
        case .markdown: return "text.quote"
        case .shell: return "terminal"
        case .unknown: return "doc.text"
        }
    }
}

// MARK: - Diff View Mode

public enum DiffViewMode: String, Sendable, CaseIterable {
    case sideBySide = "Split"
    case unified = "Unified"
}

public enum DiffLineSide: Sendable {
    case left
    case right
    case unified
}

// MARK: - Diff Stats

public struct DiffStats: Sendable {
    public let filesChanged: Int
    public let insertions: Int
    public let deletions: Int

    public init(filesChanged: Int, insertions: Int, deletions: Int) {
        self.filesChanged = filesChanged
        self.insertions = insertions
        self.deletions = deletions
    }
}

// MARK: - Diff Viewer State

@MainActor
public final class DiffViewerState: ObservableObject {
    @Published public var files: [DiffFile]
    @Published public var selectedFileID: UUID?
    @Published public var viewMode: DiffViewMode
    @Published public var searchQuery: String
    @Published public var isSearchActive: Bool
    @Published public var contextLineCount: Int

    public var onApply: ((DiffHunk) -> Void)?
    public var onDiscard: ((DiffHunk) -> Void)?

    public init(
        files: [DiffFile] = [],
        viewMode: DiffViewMode = .sideBySide,
        searchQuery: String = "",
        isSearchActive: Bool = false,
        contextLineCount: Int = 3,
        onApply: ((DiffHunk) -> Void)? = nil,
        onDiscard: ((DiffHunk) -> Void)? = nil
    ) {
        self.files = files
        self.selectedFileID = files.first?.id
        self.viewMode = viewMode
        self.searchQuery = searchQuery
        self.isSearchActive = isSearchActive
        self.contextLineCount = contextLineCount
        self.onApply = onApply
        self.onDiscard = onDiscard
    }

    public var selectedFile: DiffFile? {
        guard let id = selectedFileID else { return files.first }
        return files.first { $0.id == id }
    }

    public var selectedFileIndex: Int {
        guard let id = selectedFileID,
              let idx = files.firstIndex(where: { $0.id == id }) else { return 0 }
        return idx
    }

    public var stats: DiffStats {
        DiffStats(
            filesChanged: files.count,
            insertions: files.reduce(0) { $0 + $1.additions },
            deletions: files.reduce(0) { $0 + $1.deletions }
        )
    }

    public func selectNextFile() {
        let nextIdx = min(files.count - 1, selectedFileIndex + 1)
        selectedFileID = files[nextIdx].id
    }

    public func selectPreviousFile() {
        let prevIdx = max(0, selectedFileIndex - 1)
        selectedFileID = files[prevIdx].id
    }
}

// MARK: - Main Diff Viewer Component

public struct DiffViewer: View {
    @ObservedObject public var state: DiffViewerState

    public init(state: DiffViewerState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Unified Top Navigation Bar
            DiffTopBar(state: state)

            Divider()
                .foregroundStyle(Color.adDivider)

            // Main Diff Comparison Canvas
            if let file = state.selectedFile {
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(file.hunks) { hunk in
                            HunkView(hunk: hunk, viewMode: state.viewMode, state: state)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.adTextTertiary)
                    Text("No Modified Files in Working Tree")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.adTextSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.adBackground)
    }
}

// MARK: - Diff Top Bar

struct DiffTopBar: View {
    @ObservedObject var state: DiffViewerState

    var body: some View {
        HStack(spacing: 12) {
            // File Switcher Dropdown & Nav Arrows
            HStack(spacing: 4) {
                Button {
                    state.selectPreviousFile()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(state.selectedFileIndex > 0 ? Color.adTextPrimary : Color.adTextTertiary)
                }
                .buttonStyle(.plain)
                .disabled(state.selectedFileIndex <= 0)

                Menu {
                    ForEach(state.files) { file in
                        Button {
                            state.selectedFileID = file.id
                        } label: {
                            HStack {
                                Text(file.filePath)
                                if (state.selectedFileID ?? state.files.first?.id) == file.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if let file = state.selectedFile {
                            Image(systemName: file.language.icon)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.adOrange)

                            Text(file.filePath)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.adTextPrimary)

                            Text("(\(state.selectedFileIndex + 1) of \(state.files.count))")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.adTextTertiary)
                        } else {
                            Text("Select File...")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.adTextSecondary)
                        }
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.adTextTertiary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.adElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .menuStyle(.borderlessButton)

                Button {
                    state.selectNextFile()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(state.selectedFileIndex < state.files.count - 1 ? Color.adTextPrimary : Color.adTextTertiary)
                }
                .buttonStyle(.plain)
                .disabled(state.selectedFileIndex >= state.files.count - 1)
            }

            // Stats pill
            if let file = state.selectedFile {
                HStack(spacing: 4) {
                    Text("+\(file.additions)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.adSuccess)
                    Text("-\(file.deletions)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.adError)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.adElevated)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(file.filePath, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.adTextTertiary)
                }
                .buttonStyle(.plain)
                .help("Copy file path")
            }

            Spacer()

            // View Mode Toggle (No vertical label wrapping)
            Picker("", selection: $state.viewMode) {
                ForEach(DiffViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 140)

            // Context Lines Stepper
            HStack(spacing: 3) {
                Text("Context:")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.adTextTertiary)

                Button("-") {
                    state.contextLineCount = max(1, state.contextLineCount - 1)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.adTextSecondary)
                .padding(.horizontal, 4)

                Text("\(state.contextLineCount)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.adTextPrimary)

                Button("+") {
                    state.contextLineCount = min(10, state.contextLineCount + 1)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.adTextSecondary)
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.adElevated)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.adNavy.opacity(0.95))
    }
}

// MARK: - Hunk Card View

struct HunkView: View {
    let hunk: DiffHunk
    let viewMode: DiffViewMode
    @ObservedObject var state: DiffViewerState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hunk Header Banner
            HStack(spacing: 8) {
                Text(hunk.header)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.adInfo)

                Spacer()

                HStack(spacing: 6) {
                    Text("+\(hunk.additions) / -\(hunk.deletions)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.adTextTertiary)

                    Button("Stage Hunk") {
                        state.onApply?(hunk)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.adSuccess)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.adSuccess.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    Button("Revert Hunk") {
                        state.onDiscard?(hunk)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.adError)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.adError.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.adElevated)

            Divider()
                .foregroundStyle(Color.adDivider)

            // Code Table
            if viewMode == .unified {
                VStack(spacing: 0) {
                    ForEach(hunk.lines) { line in
                        UnifiedLineRow(line: line)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    // Split Column Headers
                    HStack(spacing: 0) {
                        Text("ORIGINAL")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.adTextTertiary)
                            .padding(.leading, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Rectangle()
                            .fill(Color.adDivider)
                            .frame(width: 1)

                        Text("MODIFIED")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.adTextTertiary)
                            .padding(.leading, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 3)
                    .background(Color.adNavy.opacity(0.5))

                    Divider()
                        .foregroundStyle(Color.adDivider)

                    ForEach(pairedLines(hunk.lines), id: \.offset) { _, pair in
                        SplitLineRow(left: pair.left, right: pair.right)
                    }
                }
            }
        }
        .background(Color.adBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.adDivider, lineWidth: 1)
        )
    }

    private func pairedLines(_ lines: [DiffLine]) -> [(offset: Int, pair: (left: DiffLine?, right: DiffLine?))] {
        var pairs: [(left: DiffLine?, right: DiffLine?)] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            switch line.type {
            case .addition:
                pairs.append((left: nil, right: line))
            case .deletion:
                if i + 1 < lines.count && lines[i + 1].type == .addition {
                    pairs.append((left: line, right: lines[i + 1]))
                    i += 1
                } else {
                    pairs.append((left: line, right: nil))
                }
            case .context, .modification:
                pairs.append((left: line, right: line))
            default:
                break
            }
            i += 1
        }
        return Array(pairs.enumerated()).map { (offset: $0.offset, pair: $0.element) }
    }
}

// MARK: - Unified Line Row

struct UnifiedLineRow: View {
    let line: DiffLine

    private var lineBg: Color {
        switch line.type {
        case .addition: return Color.adSuccess.opacity(0.12)
        case .deletion: return Color.adError.opacity(0.12)
        default: return Color.clear
        }
    }

    private var lineBorder: Color {
        switch line.type {
        case .addition: return Color.adSuccess
        case .deletion: return Color.adError
        default: return Color.clear
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Old line num
            Text(line.oldLineNum.map(String.init) ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.adTextTertiary)
                .frame(width: 44, alignment: .trailing)
                .padding(.trailing, 6)

            // New line num
            Text(line.newLineNum.map(String.init) ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.adTextTertiary)
                .frame(width: 44, alignment: .trailing)
                .padding(.trailing, 8)

            // Prefix (+ / - / space)
            Text(line.type.prefix)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(lineBorder.opacity(0.9))
                .frame(width: 14, alignment: .center)

            // Content
            Text(line.content)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(line.type == .deletion ? Color.adTextSecondary : Color.adTextPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)
        }
        .padding(.vertical, 2)
        .background(lineBg)
        .overlay(alignment: .leading) {
            if line.type != .context {
                Rectangle()
                    .fill(lineBorder)
                    .frame(width: 3)
            }
        }
    }
}

// MARK: - Split (Side-by-Side) Line Row

struct SplitLineRow: View {
    let left: DiffLine?
    let right: DiffLine?

    var body: some View {
        HStack(spacing: 0) {
            // Left Pane (Old)
            SplitCell(line: left, side: .left)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Divider
            Rectangle()
                .fill(Color.adDivider)
                .frame(width: 1)

            // Right Pane (New)
            SplitCell(line: right, side: .right)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SplitCell: View {
    let line: DiffLine?
    let side: DiffLineSide

    private var cellBg: Color {
        guard let line = line else { return Color.adElevated.opacity(0.2) }
        switch line.type {
        case .addition: return Color.adSuccess.opacity(0.12)
        case .deletion: return Color.adError.opacity(0.12)
        default: return Color.clear
        }
    }

    private var cellBorder: Color {
        guard let line = line else { return Color.clear }
        switch line.type {
        case .addition: return Color.adSuccess
        case .deletion: return Color.adError
        default: return Color.clear
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            if let line = line {
                // Line Number
                let num = side == .left ? (line.oldLineNum.map(String.init) ?? "") : (line.newLineNum.map(String.init) ?? "")
                Text(num)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.adTextTertiary)
                    .frame(width: 38, alignment: .trailing)
                    .padding(.trailing, 6)

                // Prefix
                Text(line.type.prefix)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(cellBorder.opacity(0.9))
                    .frame(width: 12, alignment: .center)

                // Text
                Text(line.content)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(line.type == .deletion ? Color.adTextSecondary : Color.adTextPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 6)
            } else {
                // Empty counterpart cell with subtle diagonal placeholder
                Text("")
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 2)
        .background(cellBg)
        .overlay(alignment: .leading) {
            if let line = line, line.type != .context {
                Rectangle()
                    .fill(cellBorder)
                    .frame(width: 3)
            }
        }
    }
}
