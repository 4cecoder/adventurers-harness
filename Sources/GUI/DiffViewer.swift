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
    @Published public var showsFileSidebar: Bool
    @Published public var isLoadingLiveDiff: Bool

    public var onApply: ((DiffHunk) -> Void)?
    public var onDiscard: ((DiffHunk) -> Void)?

    public init(
        files: [DiffFile] = [],
        viewMode: DiffViewMode = .sideBySide,
        searchQuery: String = "",
        isSearchActive: Bool = false,
        contextLineCount: Int = 3,
        showsFileSidebar: Bool = true,
        onApply: ((DiffHunk) -> Void)? = nil,
        onDiscard: ((DiffHunk) -> Void)? = nil
    ) {
        self.files = files
        self.selectedFileID = files.first?.id
        self.viewMode = viewMode
        self.searchQuery = searchQuery
        self.isSearchActive = isSearchActive
        self.contextLineCount = contextLineCount
        self.showsFileSidebar = showsFileSidebar
        self.isLoadingLiveDiff = false
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
        guard !files.isEmpty else { return }
        let nextIdx = min(files.count - 1, selectedFileIndex + 1)
        selectedFileID = files[nextIdx].id
    }

    public func selectPreviousFile() {
        guard !files.isEmpty else { return }
        let prevIdx = max(0, selectedFileIndex - 1)
        selectedFileID = files[prevIdx].id
    }

    /// Loads actual git working directory diffs
    public func loadLiveGitDiff(workspacePath: String = FileManager.default.currentDirectoryPath) {
        Task {
            self.isLoadingLiveDiff = true
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["diff", "HEAD", "--no-color"]
            process.currentDirectoryURL = URL(fileURLWithPath: workspacePath)
            process.standardOutput = pipe

            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if let rawDiff = String(data: data, encoding: .utf8), !rawDiff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let parsed = GitDiffParser.parse(rawDiff)
                    if !parsed.isEmpty {
                        self.files = parsed
                        if self.selectedFileID == nil || !parsed.contains(where: { $0.id == self.selectedFileID }) {
                            self.selectedFileID = parsed.first?.id
                        }
                    }
                }
            } catch {
                // If git fails, preserve existing seeded diffs
            }
            self.isLoadingLiveDiff = false
        }
    }
}

// MARK: - Git Diff Parser

public struct GitDiffParser {
    public static func parse(_ raw: String) -> [DiffFile] {
        var files: [DiffFile] = []
        let rawFiles = raw.components(separatedBy: "\ndiff --git ")

        for rawFile in rawFiles {
            let block = rawFile.hasPrefix("diff --git ") ? rawFile : "diff --git " + rawFile
            guard let file = parseSingleFile(block) else { continue }
            files.append(file)
        }
        return files
    }

    private static func parseSingleFile(_ block: String) -> DiffFile? {
        let lines = block.components(separatedBy: .newlines)
        guard let firstLine = lines.first(where: { $0.hasPrefix("diff --git ") }) else { return nil }

        // Extract file path from "diff --git a/path b/path"
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 4 else { return nil }
        var rawPath = parts[3]
        if rawPath.hasPrefix("b/") {
            rawPath = String(rawPath.dropFirst(2))
        }

        var hunks: [DiffHunk] = []
        var currentHunkLines: [DiffLine] = []
        var currentHeader = ""
        var oldStart = 1, oldCount = 0, newStart = 1, newCount = 0
        var oldLine = 1, newLine = 1

        for line in lines {
            if line.hasPrefix("@@") {
                // Save previous hunk
                if !currentHunkLines.isEmpty {
                    hunks.append(DiffHunk(
                        header: currentHeader,
                        oldStart: oldStart,
                        oldCount: oldCount,
                        newStart: newStart,
                        newCount: newCount,
                        lines: currentHunkLines
                    ))
                    currentHunkLines = []
                }
                currentHeader = line
                // Parse @@ -A,B +C,D @@
                let regex = try? NSRegularExpression(pattern: #"@@\s*-(\d+)(?:,(\d+))?\s*\+(\d+)(?:,(\d+))?\s*@@"#)
                if let match = regex?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                    if let r1 = Range(match.range(at: 1), in: line), let v = Int(line[r1]) { oldStart = v; oldLine = v }
                    if let r2 = Range(match.range(at: 2), in: line), let v = Int(line[r2]) { oldCount = v }
                    if let r3 = Range(match.range(at: 3), in: line), let v = Int(line[r3]) { newStart = v; newLine = v }
                    if let r4 = Range(match.range(at: 4), in: line), let v = Int(line[r4]) { newCount = v }
                }
            } else if line.hasPrefix("+") && !line.hasPrefix("+++") {
                currentHunkLines.append(DiffLine(type: .addition, content: String(line.dropFirst()), oldLineNum: nil, newLineNum: newLine))
                newLine += 1
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                currentHunkLines.append(DiffLine(type: .deletion, content: String(line.dropFirst()), oldLineNum: oldLine, newLineNum: nil))
                oldLine += 1
            } else if line.hasPrefix(" ") {
                currentHunkLines.append(DiffLine(type: .context, content: String(line.dropFirst()), oldLineNum: oldLine, newLineNum: newLine))
                oldLine += 1
                newLine += 1
            }
        }

        if !currentHunkLines.isEmpty {
            hunks.append(DiffHunk(
                header: currentHeader,
                oldStart: oldStart,
                oldCount: oldCount,
                newStart: newStart,
                newCount: newCount,
                lines: currentHunkLines
            ))
        }

        guard !hunks.isEmpty else { return nil }
        return DiffFile(filePath: rawPath, hunks: hunks)
    }
}

// MARK: - Main Full-Width Diff Viewer Component

public struct DiffViewer: View {
    @ObservedObject public var state: DiffViewerState

    public init(state: DiffViewerState) {
        self.state = state
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Optional Collapsible Files Sidebar
            if state.showsFileSidebar && state.files.count > 1 {
                DiffFileListView(state: state)
                    .frame(width: 250)
                    .transition(.move(edge: .leading).combined(with: .opacity))

                Divider()
                    .foregroundStyle(Color.adDivider)
            }

            // Main Diff Comparison Stage
            VStack(spacing: 0) {
                // Unified Top Navigation Bar
                DiffTopBar(state: state)

                Divider()
                    .foregroundStyle(Color.adDivider)

                // Expansive Diff Canvas
                if let file = state.selectedFile {
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(file.hunks) { hunk in
                                HunkView(hunk: hunk, viewMode: state.viewMode, state: state)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Empty state
                    emptyStateView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.adBackground)
        .onAppear {
            state.loadLiveGitDiff()
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 38))
                .foregroundStyle(Color.adTextTertiary)
            Text("No Modified Files in Working Tree")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.adTextSecondary)
            Text("When the agent creates or edits files, full-width diff comparisons will appear here.")
                .font(.system(size: 12))
                .foregroundStyle(Color.adTextTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            Button("Check Live Git Diff") {
                state.loadLiveGitDiff()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.adOrange)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.adElevated)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Diff File List Sidebar (Drawer)

struct DiffFileListView: View {
    @ObservedObject var state: DiffViewerState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("MODIFIED FILES (\(state.files.count))")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.adTextTertiary)

                Spacer()

                HStack(spacing: 4) {
                    Text("+\(state.stats.insertions)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.adSuccess)
                    Text("-\(state.stats.deletions)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.adError)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.adNavy.opacity(0.6))

            Divider()
                .foregroundStyle(Color.adDivider)

            // File items
            ScrollView(.vertical) {
                LazyVStack(spacing: 2) {
                    ForEach(state.files) { file in
                        let isSelected = (state.selectedFileID ?? state.files.first?.id) == file.id
                        Button {
                            state.selectedFileID = file.id
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: file.language.icon)
                                    .font(.system(size: 12))
                                    .foregroundStyle(isSelected ? Color.adOrange : Color.adTextSecondary)
                                    .frame(width: 16)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.fileName)
                                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular, design: .monospaced))
                                        .foregroundStyle(isSelected ? Color.adTextPrimary : Color.adTextSecondary)
                                        .lineLimit(1)

                                    Text(file.directoryPath)
                                        .font(.system(size: 9))
                                        .foregroundStyle(Color.adTextTertiary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                HStack(spacing: 3) {
                                    Text("+\(file.additions)")
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(Color.adSuccess)
                                    Text("-\(file.deletions)")
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(Color.adError)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isSelected ? Color.adOverlay : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
            }
        }
        .background(Color.adNavy.opacity(0.85))
    }
}

// MARK: - Diff Top Bar

struct DiffTopBar: View {
    @ObservedObject var state: DiffViewerState

    var body: some View {
        HStack(spacing: 12) {
            // Sidebar Toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    state.showsFileSidebar.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(state.showsFileSidebar ? Color.adOrange : Color.adTextTertiary)
            }
            .buttonStyle(.plain)
            .help("Toggle Files Sidebar")

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

            // Refresh Live Git Diff
            Button {
                state.loadLiveGitDiff()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .bold))
                    Text("Refresh")
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.adElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(Color.adTextSecondary)
            }
            .buttonStyle(.plain)
            .help("Refresh working tree git diff")

            // View Mode Toggle (Split / Unified)
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

// MARK: - Full-Width Hunk Card View

struct HunkView: View {
    let hunk: DiffHunk
    let viewMode: DiffViewMode
    @ObservedObject var state: DiffViewerState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hunk Header Banner
            HStack(spacing: 8) {
                Image(systemName: "number")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.adInfo)

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
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.adSuccess.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    Button("Revert Hunk") {
                        state.onDiscard?(hunk)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.adError)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.adError.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
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
                        Text("ORIGINAL / BASE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.adTextTertiary)
                            .padding(.leading, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Rectangle()
                            .fill(Color.adDivider)
                            .frame(width: 1)

                        Text("MODIFIED / HEAD")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.adTextTertiary)
                            .padding(.leading, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                    .background(Color.adNavy.opacity(0.6))

                    Divider()
                        .foregroundStyle(Color.adDivider)

                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(spacing: 0) {
                            ForEach(pairedLines(hunk.lines), id: \.offset) { _, pair in
                                SplitLineRow(left: pair.left, right: pair.right)
                            }
                        }
                        .frame(minWidth: 800, maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.adBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
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
                .frame(width: 46, alignment: .trailing)
                .padding(.trailing, 6)

            // New line num
            Text(line.newLineNum.map(String.init) ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.adTextTertiary)
                .frame(width: 46, alignment: .trailing)
                .padding(.trailing, 8)

            // Prefix (+ / - / space)
            Text(line.type.prefix)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(lineBorder.opacity(0.9))
                .frame(width: 16, alignment: .center)

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
                .frame(minWidth: 400, maxWidth: .infinity, alignment: .leading)

            // Divider
            Rectangle()
                .fill(Color.adDivider)
                .frame(width: 1)

            // Right Pane (New)
            SplitCell(line: right, side: .right)
                .frame(minWidth: 400, maxWidth: .infinity, alignment: .leading)
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
                    .frame(width: 42, alignment: .trailing)
                    .padding(.trailing, 6)

                // Prefix
                Text(line.type.prefix)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(cellBorder.opacity(0.9))
                    .frame(width: 14, alignment: .center)

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
