// AdventurersHarness - Thread List Sidebar
// Left sidebar showing agent threads, inspired by Codex's multi-agent organization.

import SwiftUI

// MARK: - Thread Status

/// Status of an agent thread with associated SF Symbol and color.
public enum ThreadStatus: String, Sendable, CaseIterable, Codable {
    case running
    case paused
    case completed
    case failed
    case stopped

    /// SF Symbol name for this status.
    public var symbolName: String {
        switch self {
        case .running:   "arrow.triangle.2.circlepath"
        case .paused:    "pause.circle.fill"
        case .completed: "checkmark.circle.fill"
        case .failed:    "xmark.circle.fill"
        case .stopped:   "stop.circle.fill"
        }
    }

    /// Accent color for this status.
    public var color: Color {
        switch self {
        case .running:   .adOrange
        case .paused:    .adWarning
        case .completed: .adSuccess
        case .failed:    .adError
        case .stopped:   .adTextTertiary
        }
    }

    /// Localized label.
    public var label: String {
        switch self {
        case .running:   "Running"
        case .paused:    "Paused"
        case .completed: "Completed"
        case .failed:    "Failed"
        case .stopped:   "Stopped"
        }
    }
}

// MARK: - Thread Item

/// A single agent thread displayed in the sidebar.
public struct ThreadItem: Identifiable, Sendable, Hashable {
    public let id: UUID
    public var name: String
    public var status: ThreadStatus
    public var summary: String
    public var lastActivity: Date
    public var createdAt: Date
    public var agentName: String
    public var isArchived: Bool
    public var isPinned: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        status: ThreadStatus = .running,
        summary: String = "",
        lastActivity: Date = Date(),
        createdAt: Date = Date(),
        agentName: String = "Adventurer",
        isArchived: Bool = false,
        isPinned: Bool = false
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.summary = summary
        self.lastActivity = lastActivity
        self.createdAt = createdAt
        self.agentName = agentName
        self.isArchived = isArchived
        self.isPinned = isPinned
    }
}

// MARK: - Thread View Model

/// Observable state container for the thread list sidebar.
@Observable
@MainActor
final class ThreadListViewModel {
    var threads: [ThreadItem] = []
    var searchText: String = ""
    var selectedThreadID: UUID?
    var isCreatingThread: Bool = false

    /// Filtered threads grouped by status.
    var activeThreads: [ThreadItem] {
        threads
            .filter { $0.status == .running }
            .sorted { $0.lastActivity > $1.lastActivity }
    }

    var completedThreads: [ThreadItem] {
        threads
            .filter { $0.status != .running }
            .sorted { $0.lastActivity > $1.lastActivity }
    }

    /// Search-filtered active threads.
    var filteredActiveThreads: [ThreadItem] {
        guard !searchText.isEmpty else { return activeThreads }
        return activeThreads.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
            || $0.summary.localizedCaseInsensitiveContains(searchText)
            || $0.agentName.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Search-filtered completed threads.
    var filteredCompletedThreads: [ThreadItem] {
        guard !searchText.isEmpty else { return completedThreads }
        return completedThreads.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
            || $0.summary.localizedCaseInsensitiveContains(searchText)
            || $0.agentName.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Whether the list is empty after filtering.
    var isEmpty: Bool {
        filteredActiveThreads.isEmpty && filteredCompletedThreads.isEmpty
    }

    // MARK: - Actions

    func createThread(name: String? = nil) {
        let thread = ThreadItem(
            name: name ?? "New Adventure",
            status: .running,
            summary: "Awaiting task assignment..."
        )
        threads.insert(thread, at: 0)
        selectedThreadID = thread.id
    }

    func deleteThread(_ thread: ThreadItem) {
        threads.removeAll { $0.id == thread.id }
        if selectedThreadID == thread.id {
            selectedThreadID = nil
        }
    }

    func renameThread(_ thread: ThreadItem, to newName: String) {
        guard let index = threads.firstIndex(where: { $0.id == thread.id }) else { return }
        threads[index].name = newName
    }

    func duplicateThread(_ thread: ThreadItem) {
        let duplicate = ThreadItem(
            name: "\(thread.name) (Copy)",
            status: thread.status,
            summary: thread.summary,
            lastActivity: .now,
            agentName: thread.agentName
        )
        if let index = threads.firstIndex(where: { $0.id == thread.id }) {
            threads.insert(duplicate, at: index + 1)
        } else {
            threads.append(duplicate)
        }
    }

    func updateStatus(_ thread: ThreadItem, to status: ThreadStatus) {
        guard let index = threads.firstIndex(where: { $0.id == thread.id }) else { return }
        threads[index].status = status
        threads[index].lastActivity = .now
    }

    /// Seed with preview data for design iteration.
    func loadPreviewData() {
        threads = [
            ThreadItem(
                name: "Refactor auth module",
                status: .running,
                summary: "Migrating JWT validation to async/await pattern",
                agentName: "Coder"
            ),
            ThreadItem(
                name: "Fix CI pipeline",
                status: .running,
                summary: "Investigating flaky test in TestUserModel",
                agentName: "Tester"
            ),
            ThreadItem(
                name: "Add dark mode support",
                status: .completed,
                summary: "Implemented system-wide appearance switching",
                lastActivity: Date().addingTimeInterval(-3600),
                agentName: "Designer"
            ),
            ThreadItem(
                name: "Database migration",
                status: .completed,
                summary: "Schema v3 → v4 with rollback support",
                lastActivity: Date().addingTimeInterval(-7200),
                agentName: "Coder"
            ),
            ThreadItem(
                name: "Performance audit",
                status: .failed,
                summary: "Timed out during Instruments profiling session",
                lastActivity: Date().addingTimeInterval(-86400),
                agentName: "Auditor"
            ),
        ]
        selectedThreadID = threads.first?.id
    }
}

// MARK: - Thread Row View

/// A single row representing one agent thread in the sidebar.
struct ThreadRowView: View {
    let thread: ThreadItem
    @State private var isHovering = false
    @State private var pulseOpacity: Double = 1.0

    var body: some View {
        HStack(spacing: 10) {
            // Agent avatar circle
            agentAvatar
                .frame(width: 36, height: 36)

            // Text content
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(thread.name)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer()

                    statusIndicator
                }

                Text(thread.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    Text(thread.agentName)
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Circle()
                        .fill(.tertiary)
                        .frame(width: 3, height: 3)

                    Text(thread.lastActivity, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Color.accentColor.opacity(0.08) : Color.clear)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onAppear {
            if thread.status == .running {
                startPulseAnimation()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(thread.name), \(thread.status.label), by \(thread.agentName)")
        .accessibilityHint("Double click to open thread")
    }

    // MARK: - Subviews

    private var agentAvatar: some View {
        ZStack {
            Circle()
                .fill(thread.status.color.opacity(0.15))

            Image(systemName: agentSymbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(thread.status.color)
                .opacity(thread.status == .running ? pulseOpacity : 1.0)
        }
    }

    private var statusIndicator: some View {
        Image(systemName: thread.status.symbolName)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(thread.status.color)
            .symbolEffect(.variableColor.iterative, isActive: thread.status == .running)
    }

    private var agentSymbol: String {
        switch thread.agentName.lowercased() {
        case "coder":    return "chevron.left.forwardslash.chevron.right"
        case "tester":   return "checkmark.shield"
        case "designer": return "paintbrush"
        case "auditor":  return "magnifyingglass"
        default:         return "person.fill"
        }
    }

    // MARK: - Animation

    private func startPulseAnimation() {
        withAnimation(
            .easeInOut(duration: 1.2)
            .repeatForever(autoreverses: true)
        ) {
            pulseOpacity = 0.4
        }
    }
}

// MARK: - Thread List View

/// Left sidebar displaying all agent threads, organized by status.
struct ThreadListView: View {
    @State private var viewModel = ThreadListViewModel()
    @State private var threadToDelete: ThreadItem?
    @State private var threadToRename: ThreadItem?
    @State private var renameText: String = ""
    @State private var isShowingNewThreadAlert = false
    @State private var newThreadName: String = ""

    var body: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            detailPlaceholder
        }
        .navigationTitle("Threads")
        .onAppear {
            viewModel.loadPreviewData()
        }
        .alert("New Thread", isPresented: $isShowingNewThreadAlert) {
            TextField("Thread name", text: $newThreadName)
            Button("Create") {
                viewModel.createThread(name: newThreadName.isEmpty ? nil : newThreadName)
                newThreadName = ""
            }
            Button("Cancel", role: .cancel) {
                newThreadName = ""
            }
        } message: {
            Text("Give your adventure a name.")
        }
        .alert("Rename Thread", isPresented: Binding(
            get: { threadToRename != nil },
            set: { if !$0 { threadToRename = nil } }
        )) {
            TextField("Thread name", text: $renameText)
            Button("Rename") {
                if let thread = threadToRename, !renameText.isEmpty {
                    viewModel.renameThread(thread, to: renameText)
                }
                threadToRename = nil
                renameText = ""
            }
            Button("Cancel", role: .cancel) {
                threadToRename = nil
                renameText = ""
            }
        } message: {
            Text("Enter a new name for this thread.")
        }
    }

    // MARK: - Sidebar Content

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            // New thread button
            newThreadButton
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            if viewModel.isEmpty {
                emptyState
            } else {
                threadList
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))

            TextField("Search threads...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private var newThreadButton: some View {
        Button {
            isShowingNewThreadAlert = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                Text("New Thread")
                    .font(.system(size: 13, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.12))
            )
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Create new thread")
        .accessibilityHint("Opens a dialog to name and create a new agent thread")
    }

    private var threadList: some View {
        List(selection: $viewModel.selectedThreadID) {
            // Active section
            if !viewModel.filteredActiveThreads.isEmpty {
                Section {
                    ForEach(viewModel.filteredActiveThreads) { thread in
                        threadRow(thread)
                            .tag(thread.id)
                            .contextMenu {
                                threadContextMenu(for: thread)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    threadToDelete = thread
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    sectionHeader("Active", count: viewModel.filteredActiveThreads.count, color: .orange)
                }
            }

            // Completed section
            if !viewModel.filteredCompletedThreads.isEmpty {
                Section {
                    ForEach(viewModel.filteredCompletedThreads) { thread in
                        threadRow(thread)
                            .tag(thread.id)
                            .contextMenu {
                                threadContextMenu(for: thread)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    threadToDelete = thread
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    sectionHeader(
                        "Completed",
                        count: viewModel.filteredCompletedThreads.count,
                        color: .green
                    )
                }
            }
        }
        .listStyle(.sidebar)
        .confirmationDialog(
            "Delete Thread?",
            isPresented: Binding(
                get: { threadToDelete != nil },
                set: { if !$0 { threadToDelete = nil } }
            ),
            presenting: threadToDelete
        ) { thread in
            Button("Delete", role: .destructive) {
                viewModel.deleteThread(thread)
            }
        } message: { thread in
            Text("Are you sure you want to delete \"\(thread.name)\"? This cannot be undone.")
        }
    }

    private func threadRow(_ thread: ThreadItem) -> some View {
        ThreadRowView(thread: thread)
            .padding(.vertical, 2)
    }

    private func sectionHeader(_ title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
            Spacer()
            Text("\(count)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    Capsule()
                        .fill(color.opacity(0.15))
                )
        }
        .padding(.vertical, 2)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func threadContextMenu(for thread: ThreadItem) -> some View {
        Button {
            renameText = thread.name
            threadToRename = thread
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Divider()

        Button {
            viewModel.duplicateThread(thread)
        } label: {
            Label("Duplicate", systemImage: "doc.on.doc")
        }

        Divider()

        Button {
            exportThread(thread)
        } label: {
            Label("Export…", systemImage: "square.and.arrow.up")
        }

        Divider()

        Button(role: .destructive) {
            threadToDelete = thread
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            // Adventurers logo mark
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tertiary)
                .symbolEffect(.bounce, value: viewModel.isEmpty)

            VStack(spacing: 6) {
                Text("Start a New Adventure")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.primary)

                Text("Create a thread to begin a new agent session.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                isShowingNewThreadAlert = true
            } label: {
                Label("New Thread", systemImage: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor)
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    // MARK: - Detail Placeholder

    private var detailPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)

            Text("Select a Thread")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)

            Text("Choose a thread from the sidebar to view its conversation.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Export

    private func exportThread(_ thread: ThreadItem) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(thread.name.replacingOccurrences(of: " ", with: "_")).json"
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            let data: [String: Any] = [
                "id": thread.id.uuidString,
                "name": thread.name,
                "status": thread.status.rawValue,
                "summary": thread.summary,
                "agentName": thread.agentName,
                "lastActivity": ISO8601DateFormatter().string(from: thread.lastActivity),
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]) {
                try? jsonData.write(to: url)
            }
        }
    }
}

// MARK: - Preview

