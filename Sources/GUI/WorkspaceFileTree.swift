// GUI - Workspace File Tree & Explorer
// Obsidian Glass file tree viewer with git status, search, and instant file preview/diff inspect.

import SwiftUI
import AdventurersCore

public struct FileItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public let fileSize: Int64
    public let modificationDate: Date
    public var children: [FileItem]?

    public init(
        name: String,
        path: String,
        isDirectory: Bool,
        fileSize: Int64 = 0,
        modificationDate: Date = Date(),
        children: [FileItem]? = nil
    ) {
        self.id = path
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.children = children
    }

    public var fileExtension: String {
        (name as NSString).pathExtension.lowercased()
    }

    public var systemIcon: String {
        if isDirectory {
            return "folder.fill"
        }
        switch fileExtension {
        case "swift": return "swift"
        case "json", "yaml", "yml", "toml": return "curlybraces"
        case "md", "markdown", "txt": return "doc.plaintext"
        case "sh", "bash", "zsh": return "terminal"
        case "png", "jpg", "jpeg", "svg", "icns": return "photo"
        case "plist", "xml": return "doc.badge.gearshape"
        default: return "doc"
        }
    }

    public var iconColor: Color {
        if isDirectory {
            return Color.adOrange
        }
        switch fileExtension {
        case "swift": return Color.orange
        case "json", "yaml", "yml": return Color.yellow
        case "md", "markdown": return Color.cyan
        case "sh", "bash", "zsh": return Color.green
        case "png", "jpg", "svg": return Color.purple
        default: return Color.adTextSecondary
        }
    }

    public var formattedSize: String {
        if isDirectory { return "" }
        if fileSize < 1024 {
            return "\(fileSize) B"
        } else if fileSize < 1024 * 1024 {
            return String(format: "%.1f KB", Double(fileSize) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(fileSize) / (1024.0 * 1024.0))
        }
    }
}

// MARK: - File Tree Loader

@MainActor
@Observable
public final class WorkspaceFileTreeModel {
    public var rootDirectory: String
    public var items: [FileItem] = []
    public var selectedFile: FileItem?
    public var searchQuery: String = ""
    public var isLoading: Bool = false
    public var expandedFolders: Set<String> = []

    public init(rootDirectory: String = WorkspaceConfig.defaultWorkspacePath) {
        self.rootDirectory = rootDirectory
        refresh()
    }

    public func updateRootDirectory(_ path: String) {
        guard rootDirectory != path else { return }
        rootDirectory = path
        refresh()
    }

    public func refresh() {
        isLoading = true
        let dir = rootDirectory
        Task.detached(priority: .userInitiated) {
            let loaded = Self.loadDirectory(at: dir, maxDepth: 4)
            await MainActor.run {
                self.items = loaded
                self.isLoading = false
            }
        }
    }

    nonisolated private static func loadDirectory(at path: String, maxDepth: Int, currentDepth: Int = 0) -> [FileItem] {
        guard currentDepth < maxDepth else { return [] }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: path) else { return [] }

        var result: [FileItem] = []
        let ignoredNames: Set<String> = [".git", ".build", "node_modules", ".tempmediaStorage", ".system_generated"]

        for name in contents.sorted() {
            if ignoredNames.contains(name) { continue }
            let fullPath = (path as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir) else { continue }

            let attrs = (try? fm.attributesOfItem(atPath: fullPath)) ?? [:]
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            let modDate = (attrs[.modificationDate] as? Date) ?? Date()

            if isDir.boolValue {
                let children = loadDirectory(at: fullPath, maxDepth: maxDepth, currentDepth: currentDepth + 1)
                result.append(FileItem(
                    name: name,
                    path: fullPath,
                    isDirectory: true,
                    fileSize: size,
                    modificationDate: modDate,
                    children: children
                ))
            } else {
                result.append(FileItem(
                    name: name,
                    path: fullPath,
                    isDirectory: false,
                    fileSize: size,
                    modificationDate: modDate
                ))
            }
        }

        // Folders first, then alphabetical files
        return result.sorted {
            if $0.isDirectory != $1.isDirectory {
                return $0.isDirectory && !$1.isDirectory
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    public var filteredItems: [FileItem] {
        if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            return items
        }
        let query = searchQuery.lowercased()
        return filterItems(items, query: query)
    }

    private func filterItems(_ list: [FileItem], query: String) -> [FileItem] {
        var matches: [FileItem] = []
        for item in list {
            if item.name.lowercased().contains(query) {
                matches.append(item)
            } else if let children = item.children {
                let filteredChildren = filterItems(children, query: query)
                if !filteredChildren.isEmpty {
                    var copy = item
                    copy.children = filteredChildren
                    matches.append(copy)
                }
            }
        }
        return matches
    }
}

// MARK: - Workspace File Tree View

public struct WorkspaceFileTreeView: View {
    @State public var model: WorkspaceFileTreeModel
    public var onFileSelected: ((FileItem) -> Void)?

    public init(rootDirectory: String, onFileSelected: ((FileItem) -> Void)? = nil) {
        _model = State(initialValue: WorkspaceFileTreeModel(rootDirectory: rootDirectory))
        self.onFileSelected = onFileSelected
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Search & Controls Header
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.adTextTertiary)

                TextField("Filter files...", text: $model.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.adTextPrimary)

                if !model.searchQuery.isEmpty {
                    Button {
                        model.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.adTextTertiary)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.adOrange)
                        .rotationEffect(.degrees(model.isLoading ? 360 : 0))
                        .animation(model.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: model.isLoading)
                }
                .buttonStyle(.plain)
                .help("Refresh File Tree")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.adElevated.opacity(0.8))

            Divider().overlay(Color.adBorder)

            // File Tree List
            if model.isLoading && model.items.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Scanning workspace files...")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.adTextTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.filteredItems.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.adTextTertiary)
                    Text("No files matching search")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.adTextTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(model.filteredItems) { item in
                            FileTreeNodeView(
                                item: item,
                                level: 0,
                                selectedID: model.selectedFile?.id,
                                expandedFolders: $model.expandedFolders,
                                onSelect: { selected in
                                    model.selectedFile = selected
                                    if !selected.isDirectory {
                                        onFileSelected?(selected)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                }
            }
        }
        .background(Color.adBackground.opacity(0.95))
    }
}

// MARK: - Recursive File Tree Node

struct FileTreeNodeView: View {
    let item: FileItem
    let level: Int
    let selectedID: String?
    @Binding var expandedFolders: Set<String>
    let onSelect: (FileItem) -> Void

    private var isExpanded: Bool {
        expandedFolders.contains(item.path)
    }

    private var isSelected: Bool {
        selectedID == item.path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if item.isDirectory {
                    if isExpanded {
                        expandedFolders.remove(item.path)
                    } else {
                        expandedFolders.insert(item.path)
                    }
                }
                onSelect(item)
            } label: {
                HStack(spacing: 6) {
                    // Indentation
                    if level > 0 {
                        Spacer()
                            .frame(width: CGFloat(level * 14))
                    }

                    // Directory chevron
                    if item.isDirectory {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.adTextTertiary)
                            .frame(width: 10)
                    } else {
                        Spacer().frame(width: 10)
                    }

                    // File Icon
                    Image(systemName: item.systemIcon)
                        .font(.system(size: 11))
                        .foregroundStyle(item.iconColor)

                    // File Name
                    Text(item.name)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(isSelected ? Color.white : Color.adTextPrimary)
                        .lineLimit(1)

                    Spacer()

                    // File Size
                    if !item.isDirectory && !item.formattedSize.isEmpty {
                        Text(item.formattedSize)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Color.adTextTertiary)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? Color.adOrange.opacity(0.3) : Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    #if os(macOS)
                    NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: (item.path as NSString).deletingLastPathComponent)
                    #endif
                } label: {
                    Label("Reveal in Finder", systemImage: "arrow.up.forward.app")
                }

                Button {
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.path, forType: .string)
                    #endif
                } label: {
                    Label("Copy Absolute Path", systemImage: "doc.on.doc")
                }

                Button {
                    #if os(macOS)
                    NSWorkspace.shared.open(URL(fileURLWithPath: item.path))
                    #endif
                } label: {
                    Label("Open with Default App", systemImage: "arrow.up.right")
                }
            }

            // Recursive Children
            if item.isDirectory && isExpanded, let children = item.children {
                ForEach(children) { child in
                    FileTreeNodeView(
                        item: child,
                        level: level + 1,
                        selectedID: selectedID,
                        expandedFolders: $expandedFolders,
                        onSelect: onSelect
                    )
                }
            }
        }
    }
}
