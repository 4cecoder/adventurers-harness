//
//  AdventurersApp.swift
//  Adventurers Harness
//
//  macOS native coding agent harness — Next-gen competitor to Codex app for macOS.
//  Three-panel workspace for parallel agent threads with deterministic gate certification.
//  Built with Swift 6 and modern macOS SwiftUI.
//

import SwiftUI
import AdventurersCore

// MARK: - Workbench Mode

/// Center stage view modes for the agent workbench.
enum WorkbenchTab: String, CaseIterable, Identifiable, Sendable {
    case thread = "Thread"
    case diff = "Diffs"
    case terminal = "Terminal"
    case skills = "Skills"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .thread:   "bubble.left.and.bubble.right.fill"
        case .diff:     "arrow.triangle.branch"
        case .terminal: "terminal.fill"
        case .skills:   "puzzlepiece.extension.fill"
        }
    }

    var shortcutNumber: Int {
        switch self {
        case .thread:   1
        case .diff:     2
        case .terminal: 3
        case .skills:   4
        }
    }
}

public enum SidebarMode: String, CaseIterable, Identifiable {
    case threads = "Threads"
    case files = "Files"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .threads: return "bubble.left.and.bubble.right"
        case .files: return "folder"
        }
    }
}

// MARK: - App State

/// Top-level application state managed as an `@Observable` singleton.
/// Coordinates thread management, workbench tabs, tool executions, and inspector states.
@Observable
@MainActor
final class AppState {

    // MARK: Thread Management

    /// All open agent threads.
    var threads: [ThreadItem] = []

    /// Currently selected thread ID.
    var selectedThreadID: UUID?

    /// Search query for filtering threads in the sidebar.
    var threadSearchQuery: String = ""

    // MARK: Workbench Navigation

    /// Current active tab on the center workbench.
    var activeTab: WorkbenchTab = .thread

    /// Active model selected for execution.
    var selectedModel: String = "Claude 3.7 Sonnet"

    /// Active workspace / repository context.
    var currentWorkspace: String = "adventurers-harness"

    // MARK: Panel Visibility

    /// Current sidebar navigation mode (Threads or Workspace Files).
    var sidebarMode: SidebarMode = .threads

    /// Whether the sidebar is visible.
    var showsSidebar: Bool = true

    /// Whether the right inspector panel is visible.
    var showsInspector: Bool = false

    /// Whether the command palette (⌘K) is open.
    var showsCommandPalette: Bool = false

    // MARK: ViewModels for Active Thread

    /// Thread view models keyed by ThreadItem ID.
    var threadViewModels: [UUID: ThreadViewModel] = [:]

    /// Diff view states keyed by normalized workspace path.
    var workspaceDiffStates: [String: DiffViewerState] = [:]

    /// Gate pipeline states keyed by ThreadItem ID.
    var gateStates: [UUID: GatePipelineState] = [:]

    /// Terminal manager for live bash / runner output.
    var terminalManager = TerminalManager()

    /// Central settings model persisted across application life.
    var settingsModel = SettingsModel()

    // MARK: Initialization

    init() {
        loadThreadsFromStore()
        Task { @MainActor in
            await settingsModel.fetchLiveModelsForActiveProvider()
        }
    }

    private func loadThreadsFromStore() {
        let loaded = ThreadStore.shared.loadAllThreads()
        if !loaded.isEmpty {
            self.threads = loaded
            self.selectedThreadID = loaded.first?.id
        } else {
            createThread(name: "Initial Task: Exploration & Setup")
        }
    }

    // MARK: Computed Properties

    var selectedThread: ThreadItem? {
        guard let id = selectedThreadID else { return threads.first }
        return threads.first { $0.id == id }
    }

    var currentWorkspacePath: String {
        let raw = selectedThread?.workingDirectory ?? WorkspaceConfig.defaultWorkspacePath
        return (raw as NSString).standardizingPath
    }

    var currentThreadViewModel: ThreadViewModel {
        guard let item = selectedThread else {
            return ThreadViewModel()
        }
        if let existing = threadViewModels[item.id] {
            existing.consolidateOldMessagesIfNeeded()
            return existing
        }
        let vm = ThreadViewModel(threadID: item.id, workingDirectory: item.workingDirectory)
        vm.consolidateOldMessagesIfNeeded()
        vm.selectedModel = settingsModel.selectedModel
        vm.onMessagesChanged = { [weak self] (messages: [ThreadMessage]) in
            guard let self else { return }
            if let current = self.threads.first(where: { $0.id == item.id }) {
                var updated = current
                if let last = messages.last {
                    updated.summary = String(last.content.prefix(120))
                    updated.lastActivity = Date()
                    if let idx = self.threads.firstIndex(where: { $0.id == item.id }) {
                        self.threads[idx] = updated
                    }
                }
                ThreadStore.shared.saveThread(
                    item: updated,
                    messages: messages,
                    selectedModel: self.settingsModel.selectedModel
                )
            }
        }
        threadViewModels[item.id] = vm
        return vm
    }

    var currentDiffState: DiffViewerState {
        let path = currentWorkspacePath
        if let existing = workspaceDiffStates[path] {
            return existing
        }
        let state = DiffViewerState(workspacePath: path)
        workspaceDiffStates[path] = state
        state.loadLiveGitDiff(workspacePath: path)
        return state
    }

    var currentGateState: GatePipelineState {
        guard let id = selectedThread?.id else {
            return GatePipelineState()
        }
        if let existing = gateStates[id] {
            return existing
        }
        let state = GatePipelineState()
        gateStates[id] = state
        return state
    }

    // MARK: Actions & CRUD Operations

    func createThread(name: String? = nil, workingDirectory: String = WorkspaceConfig.defaultWorkspacePath) {
        let threadName = name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? name!
            : "Task: Adventure #\(threads.count + 1)"

        let item = ThreadItem(
            id: UUID(),
            name: threadName,
            status: .running,
            summary: "Awaiting task assignment...",
            lastActivity: Date(),
            createdAt: Date(),
            agentName: settingsModel.selectedModel.components(separatedBy: "/").last ?? "Agent",
            isArchived: false,
            isPinned: false,
            workingDirectory: workingDirectory
        )

        threads.insert(item, at: 0)
        selectedThreadID = item.id

        // Initialize thread models
        let tvm = ThreadViewModel(threadID: item.id, workingDirectory: item.workingDirectory)
        tvm.selectedModel = settingsModel.selectedModel
        tvm.onMessagesChanged = { [weak self] (messages: [ThreadMessage]) in
            guard let self else { return }
            if let current = self.threads.first(where: { $0.id == item.id }) {
                var updated = current
                if let last = messages.last {
                    updated.summary = String(last.content.prefix(120))
                    updated.lastActivity = Date()
                    if let idx = self.threads.firstIndex(where: { $0.id == item.id }) {
                        self.threads[idx] = updated
                    }
                }
                ThreadStore.shared.saveThread(
                    item: updated,
                    messages: messages,
                    selectedModel: self.settingsModel.selectedModel
                )
            }
        }
        threadViewModels[item.id] = tvm

        let diff = createSampleDiffState()
        diffStates[item.id] = diff

        let gates = GatePipelineState()
        gateStates[item.id] = gates

        // Persist initial record
        ThreadStore.shared.saveThread(
            item: item,
            messages: tvm.messages,
            selectedModel: settingsModel.selectedModel
        )

        // Add initial log to terminal session
        let session = terminalManager.createSession(name: threadName)
        session.appendCommand("harness run --thread \(item.id.uuidString.prefix(8)) --model \(settingsModel.selectedModel)")
        session.appendOutput("Initialized agent environment for workspace: \(currentWorkspace)")
    }

    func deleteThread(_ thread: ThreadItem) {
        threads.removeAll { $0.id == thread.id }
        threadViewModels.removeValue(forKey: thread.id)
        diffStates.removeValue(forKey: thread.id)
        gateStates.removeValue(forKey: thread.id)
        ThreadStore.shared.deleteThread(id: thread.id)

        if selectedThreadID == thread.id {
            selectedThreadID = threads.first?.id
        }
    }

    func setArchived(_ thread: ThreadItem, isArchived: Bool) {
        guard let index = threads.firstIndex(where: { $0.id == thread.id }) else { return }
        threads[index].isArchived = isArchived
        threads[index].status = isArchived ? .completed : .running
        threads[index].lastActivity = Date()
        ThreadStore.shared.setArchived(id: thread.id, isArchived: isArchived)
    }

    func setPinned(_ thread: ThreadItem, isPinned: Bool) {
        guard let index = threads.firstIndex(where: { $0.id == thread.id }) else { return }
        threads[index].isPinned = isPinned
        ThreadStore.shared.setPinned(id: thread.id, isPinned: isPinned)
        // Re-sort: pinned first
        threads.sort { (a: ThreadItem, b: ThreadItem) -> Bool in
            if a.isPinned != b.isPinned {
                return a.isPinned && !b.isPinned
            }
            return a.lastActivity > b.lastActivity
        }
    }

    func renameThread(_ thread: ThreadItem, to newName: String) {
        guard let index = threads.firstIndex(where: { $0.id == thread.id }) else { return }
        threads[index].name = newName
        ThreadStore.shared.renameThread(id: thread.id, newName: newName)
    }

    func duplicateThread(_ thread: ThreadItem) {
        if let dup = ThreadStore.shared.duplicateThread(id: thread.id) {
            threads.insert(dup, at: 0)
            selectedThreadID = dup.id
        }
    }

    func exportThreadMarkdown(_ thread: ThreadItem) -> String {
        let messages = ThreadStore.shared.loadMessages(for: thread.id)
        let md = ThreadStore.shared.exportMarkdown(for: thread, messages: messages)
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(md, forType: .string)
        #endif
        return md
    }

    func clearArchivedThreads() {
        threads.removeAll { $0.isArchived }
        ThreadStore.shared.clearArchivedThreads()
        if let sel = selectedThreadID, !threads.contains(where: { $0.id == sel }) {
            selectedThreadID = threads.first?.id
        }
    }

    // MARK: - Workspace Directory Management

    func activeWorkingDirectory() -> String {
        if let sel = selectedThreadID, let vm = threadViewModels[sel] {
            return vm.workingDirectory
        }
        if let sel = selectedThreadID, let thread = threads.first(where: { $0.id == sel }) {
            return thread.workingDirectory
        }
        return WorkspaceConfig.defaultWorkspacePath
    }

    func chooseAndSetWorkingDirectory(for threadID: UUID? = nil) {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose Workspace"
        panel.title = "Select Project / Working Directory"
        if panel.runModal() == .OK, let url = panel.url {
            let chosen = url.path
            let target = threadID ?? selectedThreadID
            if let target {
                updateThreadWorkingDirectory(id: target, newDirectory: chosen)
            }
        }
        #endif
    }

    func updateThreadWorkingDirectory(id: UUID, newDirectory: String) {
        if let idx = threads.firstIndex(where: { $0.id == id }) {
            threads[idx].workingDirectory = newDirectory
        }
        if let tvm = threadViewModels[id] {
            tvm.workingDirectory = newDirectory
        }
        ThreadStore.shared.updateWorkingDirectory(id: id, workingDirectory: newDirectory)
    }

    func toggleInspector() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showsInspector.toggle()
        }
    }

    func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showsSidebar.toggle()
        }
    }

    private func createSampleDiffState() -> DiffViewerState {
        return SeedData.createRichDiffState()
    }
}

// MARK: - App Entry Point

@main
struct AdventurersApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .frame(minWidth: 1000, minHeight: 650)
                .background(Color.adBackground)
        }
        .defaultSize(width: 1360, height: 860)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            AgentCommands(appState: appState)
        }

        Settings {
            SettingsView(model: appState.settingsModel)
                .environment(appState)
        }

        Window("About Adventurers Harness", id: "about-window") {
            AboutView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

// MARK: - Primary Content View (Clean macOS Three-Panel Scaffolding)

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 260, ideal: 290, max: 380)
        } detail: {
            WorkbenchContentView()
        }
        .navigationSplitViewStyle(.balanced)
        .navigationSplitViewColumnWidth(min: 260, ideal: 290, max: 380)
        .inspector(isPresented: Bindable(appState).showsInspector) {
            InspectorPanel()
                .inspectorColumnWidth(min: 260, ideal: 290, max: 360)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                // Workspace / Branch Picker Pill
                WorkspacePickerPill()
            }

            ToolbarItem(placement: .principal) {
                // Calm, minimal mode switcher
                WorkbenchTabBar()
            }

            ToolbarItemGroup(placement: .primaryAction) {
                // Cyberdeck Vibe Station Pill (Disabled by default)
                CyberdeckRadioPill()

                // Model Selector Pill
                ModelSelectorMenu()

                // Settings Button
                SettingsToolbarButton()

                // Spotlight / Command Palette Button
                Button {
                    appState.showsCommandPalette = true
                } label: {
                    Label("Spotlight Search", systemImage: "magnifyingglass")
                }
                .help("Spotlight Command Palette (⌘K)")

                // New Thread Button
                Button {
                    appState.createThread()
                } label: {
                    Label("New Thread", systemImage: "square.and.pencil")
                }
                .help("New Thread (⌘N)")

                // Inspector Toggle
                Button {
                    appState.toggleInspector()
                } label: {
                    Label("Toggle Inspector", systemImage: "sidebar.right")
                }
                .help("Toggle Inspector (⌘I)")
            }
        }
        .sheet(isPresented: Bindable(appState).showsCommandPalette) {
            CommandPaletteModal()
        }
        .sheet(isPresented: Bindable(AppUpdateManager.shared).showsUpdateModal) {
            UpdateModalView()
        }
        .onAppear {
            if appState.settingsModel.checkUpdatesOnLaunch {
                AppUpdateManager.shared.checkForUpdates(silent: true)
            }
        }
    }
}

struct SettingsToolbarButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button {
            openSettings()
        } label: {
            Label("Settings", systemImage: "gearshape")
        }
        .help("Settings & LLM Providers (⌘,)")
    }
}

// MARK: - Workspace Picker Pill

struct WorkspacePickerPill: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let currentDir = appState.activeWorkingDirectory()
        let folderName = (currentDir as NSString).lastPathComponent

        Menu {
            Section("Current Workspace Scope") {
                Text(currentDir)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.adTextTertiary)
            }

            Divider()

            Button {
                appState.chooseAndSetWorkingDirectory()
            } label: {
                Label("Open Project Folder... (⌘O)", systemImage: "folder.badge.plus")
            }

            Button {
                #if os(macOS)
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: currentDir)
                #endif
            } label: {
                Label("Reveal in Finder", systemImage: "arrow.up.forward.app")
            }

            Button {
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(currentDir, forType: .string)
                #endif
            } label: {
                Label("Copy Absolute Path", systemImage: "doc.on.doc")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.adOrange)

                Text(folderName.isEmpty ? "workspace" : folderName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.adTextPrimary)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.adTextTertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.adElevated)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .help("Active Workspace: \(currentDir)")
    }
}

// MARK: - Global Agent & Model Selector Menu

struct ModelSelectorMenu: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Menu {
            Section("Execution Strategy") {
                ForEach(ExecutionMode.allCases, id: \.self) { mode in
                    Button {
                        appState.settingsModel.executionMode = mode
                    } label: {
                        HStack {
                            Image(systemName: mode.icon)
                            Text(mode.rawValue)
                            if appState.settingsModel.executionMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            if appState.settingsModel.executionMode == .metaHarness {
                Section("Meta Harness CLIs") {
                    ForEach(MetaHarnessType.allCases) { harness in
                        Button {
                            appState.settingsModel.selectedMetaHarness = harness
                        } label: {
                            HStack {
                                Image(systemName: harness.icon)
                                Text("\(harness.rawValue) \(harness.isInstalled ? "✓" : "(not installed)")")
                                if appState.settingsModel.selectedMetaHarness == harness {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } else {
                Section("Active Provider / Subscription") {
                    ForEach(ProviderType.allCases, id: \.self) { provider in
                        Button {
                            appState.settingsModel.activeProvider = provider
                        } label: {
                            HStack {
                                Image(systemName: provider.icon)
                                Text(provider.rawValue)
                                if appState.settingsModel.activeProvider == provider {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                let providerModels = appState.settingsModel.modelsForActiveProvider()
                let reasoningModels = providerModels.filter {
                    let m = $0.lowercased()
                    return m.contains("reason") || m.contains("r1") || m.contains("o1") || m.contains("o3") || m.contains("thinking")
                }
                let codingModels = providerModels.filter {
                    let m = $0.lowercased()
                    return (m.contains("code") || m.contains("coder") || m.contains("glm") || m.contains("sonnet") || m.contains("mimo") || m.contains("kimi") || m.contains("qwen")) && !reasoningModels.contains($0)
                }
                let fastModels = providerModels.filter {
                    let m = $0.lowercased()
                    return (m.contains("flash") || m.contains("haiku") || m.contains("mini") || m.contains("8b")) && !reasoningModels.contains($0) && !codingModels.contains($0)
                }
                let otherModels = providerModels.filter {
                    !reasoningModels.contains($0) && !codingModels.contains($0) && !fastModels.contains($0)
                }

                if !reasoningModels.isEmpty {
                    Section("🧠 Reasoning & Thought (\(appState.settingsModel.activeProvider.rawValue))") {
                        ForEach(reasoningModels, id: \.self) { model in
                            Button {
                                appState.settingsModel.selectedModel = model
                                appState.currentThreadViewModel.selectedModel = model
                            } label: {
                                HStack {
                                    Image(systemName: "brain.head.profile")
                                    Text(model)
                                    if appState.settingsModel.selectedModel == model {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }

                if !codingModels.isEmpty {
                    Section("💻 Coding & Agentic (\(appState.settingsModel.activeProvider.rawValue))") {
                        ForEach(codingModels, id: \.self) { model in
                            Button {
                                appState.settingsModel.selectedModel = model
                                appState.currentThreadViewModel.selectedModel = model
                            } label: {
                                HStack {
                                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                                    Text(model)
                                    if appState.settingsModel.selectedModel == model {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }

                if !fastModels.isEmpty {
                    Section("⚡ Fast & Low Latency (\(appState.settingsModel.activeProvider.rawValue))") {
                        ForEach(fastModels, id: \.self) { model in
                            Button {
                                appState.settingsModel.selectedModel = model
                                appState.currentThreadViewModel.selectedModel = model
                            } label: {
                                HStack {
                                    Image(systemName: "bolt.fill")
                                    Text(model)
                                    if appState.settingsModel.selectedModel == model {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }

                if !otherModels.isEmpty {
                    Section("🌐 Frontier & General (\(appState.settingsModel.activeProvider.rawValue))") {
                        ForEach(otherModels, id: \.self) { model in
                            Button {
                                appState.settingsModel.selectedModel = model
                                appState.currentThreadViewModel.selectedModel = model
                            } label: {
                                HStack {
                                    Image(systemName: "sparkles")
                                    Text(model)
                                    if appState.settingsModel.selectedModel == model {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                let icon: String = {
                    switch appState.settingsModel.executionMode {
                    case .subscription: return "creditcard.fill"
                    case .payAsYouGo: return "key.fill"
                    case .metaHarness: return appState.settingsModel.selectedMetaHarness.icon
                    }
                }()

                let accent: Color = {
                    switch appState.settingsModel.executionMode {
                    case .subscription: return Color.cyan
                    case .payAsYouGo: return Color.adOrange
                    case .metaHarness: return Color.adInfo
                    }
                }()

                let label: String = {
                    if appState.settingsModel.executionMode == .metaHarness {
                        return "\(appState.settingsModel.selectedMetaHarness.defaultBinaryName)"
                    } else {
                        return "\(appState.settingsModel.selectedModel)"
                    }
                }()

                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accent)

                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.adTextPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: 160, alignment: .leading)

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.adTextTertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.adElevated)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.adDivider, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .help("Global Model & Agent Strategy Selector")
    }
}

// MARK: - Workbench Tab Bar (Center Header)

struct WorkbenchTabBar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 2) {
            ForEach(WorkbenchTab.allCases) { tab in
                let isSelected = appState.activeTab == tab

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        appState.activeTab = tab
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.symbolName)
                            .font(.system(size: 10))

                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(isSelected ? Color.adOverlay : Color.clear)
                    .foregroundStyle(isSelected ? Color.adTextPrimary : Color.adTextSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.adElevated)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

// MARK: - Sidebar View

enum ThreadFilterTab: String, CaseIterable, Identifiable {
    case active = "Active"
    case pinned = "Pinned"
    case archived = "Archived"

    var id: String { rawValue }
}

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedFilter: ThreadFilterTab = .active
    @State private var renamingThread: ThreadItem?
    @State private var renameText: String = ""
    @State private var toastMessage: String?

    var filteredThreads: [ThreadItem] {
        let baseList: [ThreadItem]
        switch selectedFilter {
        case .active:
            baseList = appState.threads.filter { !$0.isArchived }
        case .pinned:
            baseList = appState.threads.filter { $0.isPinned && !$0.isArchived }
        case .archived:
            baseList = appState.threads.filter { $0.isArchived }
        }

        if appState.threadSearchQuery.isEmpty {
            return baseList
        }
        return baseList.filter {
            $0.name.localizedCaseInsensitiveContains(appState.threadSearchQuery) ||
            $0.summary.localizedCaseInsensitiveContains(appState.threadSearchQuery)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Mode Switcher (Threads vs Workspace Files)
            HStack(spacing: 2) {
                ForEach(SidebarMode.allCases) { mode in
                    let isSelected = appState.sidebarMode == mode
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            appState.sidebarMode = mode
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 10))
                            Text(mode.rawValue)
                                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(isSelected ? Color.adOverlay : Color.clear)
                        .foregroundStyle(isSelected ? Color.adTextPrimary : Color.adTextSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(Color.adElevated)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .padding(.horizontal, 10)
            .padding(.top, 8)

            if appState.sidebarMode == .files {
                WorkspaceFileTreeView(rootDirectory: appState.activeWorkingDirectory()) { file in
                    appState.activeTab = .diff
                    appState.currentDiffState.loadLiveGitDiff(workspacePath: appState.activeWorkingDirectory())
                }
            } else {
                // Header & Filter Segment
                VStack(spacing: 6) {
                    // Search field
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption2)
                            .foregroundStyle(Color.adTextTertiary)

                        TextField("Search \(appState.threads.count) threads...", text: Bindable(appState).threadSearchQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))

                        if !appState.threadSearchQuery.isEmpty {
                            Button {
                                appState.threadSearchQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(Color.adTextTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.adElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    // Segmented Filter Tabs (Active / Pinned / Archived)
                    HStack(spacing: 2) {
                        ForEach(ThreadFilterTab.allCases) { tab in
                            let isSelected = selectedFilter == tab
                            let count: Int = {
                                switch tab {
                                case .active: return appState.threads.filter { !$0.isArchived }.count
                                case .pinned: return appState.threads.filter { $0.isPinned && !$0.isArchived }.count
                                case .archived: return appState.threads.filter { $0.isArchived }.count
                                }
                            }()

                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedFilter = tab
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    Text(tab.rawValue)
                                        .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                                    Text("\(count)")
                                        .font(.system(size: 9, weight: .regular))
                                        .opacity(0.7)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 3)
                                .background(isSelected ? Color.adElevated : Color.clear)
                                .foregroundStyle(isSelected ? Color.adTextPrimary : Color.adTextTertiary)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                    .background(Color.adBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            // Toast / Status banner
            if let toast = toastMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.adSuccess)
                        .font(.system(size: 10))
                    Text(toast)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.adTextPrimary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.adElevated)
                .transition(.opacity)
            }

            // Thread list
            if filteredThreads.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: selectedFilter == .archived ? "archivebox" : (selectedFilter == .pinned ? "pin.slash" : "bubble.left.and.bubble.right"))
                        .font(.system(size: 24))
                        .foregroundStyle(Color.adTextTertiary)
                    Text(selectedFilter == .archived ? "No archived threads" : (selectedFilter == .pinned ? "No pinned threads" : "No active threads"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.adTextSecondary)

                    if selectedFilter == .active {
                        Button("Create Thread") {
                            appState.createThread()
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.adOrange)
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(selection: Bindable(appState).selectedThreadID) {
                    Section {
                        ForEach(filteredThreads) { thread in
                            ThreadSidebarRow(thread: thread)
                                .tag(thread.id)
                                .contextMenu {
                                    Button {
                                        renamingThread = thread
                                        renameText = thread.name
                                    } label: {
                                        Label("Rename Thread", systemImage: "pencil")
                                    }

                                    Button {
                                        appState.setPinned(thread, isPinned: !thread.isPinned)
                                    } label: {
                                        Label(thread.isPinned ? "Unpin from Top" : "Pin to Top", systemImage: thread.isPinned ? "pin.slash" : "pin.fill")
                                    }

                                    Button {
                                        appState.setArchived(thread, isArchived: !thread.isArchived)
                                    } label: {
                                        Label(thread.isArchived ? "Restore Thread" : "Archive Thread", systemImage: thread.isArchived ? "tray.and.arrow.up" : "archivebox")
                                    }

                                    Button {
                                        appState.duplicateThread(thread)
                                    } label: {
                                        Label("Duplicate Thread", systemImage: "doc.on.doc")
                                    }

                                    Divider()

                                    Button {
                                        _ = appState.exportThreadMarkdown(thread)
                                        withAnimation {
                                            toastMessage = "Copied Markdown to Clipboard"
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                            withAnimation { toastMessage = nil }
                                        }
                                    } label: {
                                        Label("Export Transcript (Markdown)", systemImage: "square.and.arrow.up")
                                    }

                                    Divider()

                                    Button(role: .destructive) {
                                        appState.deleteThread(thread)
                                    } label: {
                                        Label("Delete Permanently", systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        HStack {
                            Text(selectedFilter.rawValue)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.adTextTertiary)
                                .textCase(.uppercase)

                            Spacer()

                            if selectedFilter == .archived && !filteredThreads.isEmpty {
                                Button("Clear All") {
                                    appState.clearArchivedThreads()
                                }
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.adError)
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            }

            // Minimal Footer
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.adSuccess)
                        .frame(width: 6, height: 6)
                    Text("\(appState.threads.filter { !$0.isArchived }.count) Active Threads")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.adTextTertiary)
                }

                Spacer()

                SettingsFooterButton()

                Button {
                    appState.createThread()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.adOrange)
                }
                .buttonStyle(.plain)
                .help("New Thread (⌘N)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.adNavy)
        }
        .background(Color.adBackground)
        .alert("Rename Thread", isPresented: Binding(
            get: { renamingThread != nil },
            set: { if !$0 { renamingThread = nil } }
        )) {
            TextField("Thread Name", text: $renameText)
            Button("Save") {
                if let t = renamingThread, !renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    appState.renameThread(t, to: renameText.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                renamingThread = nil
            }
            Button("Cancel", role: .cancel) {
                renamingThread = nil
            }
        }
    }
}

struct SettingsFooterButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button {
            openSettings()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 11))
                .foregroundStyle(Color.adTextTertiary)
        }
        .buttonStyle(.plain)
        .help("Settings & LLM Providers (⌘,)")
    }
}

// MARK: - Thread Sidebar Row

struct ThreadSidebarRow: View {
    let thread: ThreadItem

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if thread.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.adOrange)
                }

                Image(systemName: thread.isArchived ? "archivebox.fill" : thread.status.symbolName)
                    .font(.system(size: 10))
                    .foregroundStyle(thread.isArchived ? Color.adTextTertiary : thread.status.color)

                Text(thread.name)
                    .font(.system(size: 12, weight: thread.isPinned ? .bold : .medium))
                    .foregroundStyle(Color.adTextPrimary)
                    .lineLimit(1)

                Spacer()

                Text(thread.lastActivity, style: .relative)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.adTextTertiary)
            }

            Text(thread.summary.isEmpty ? "No messages yet" : thread.summary)
                .font(.system(size: 10))
                .foregroundStyle(Color.adTextSecondary)
                .lineLimit(1)
                .padding(.leading, thread.isPinned ? 14 : 16)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Workbench Content View (Center Stage)

struct WorkbenchContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.adBackground.ignoresSafeArea()

                if appState.selectedThread != nil {
                    switch appState.activeTab {
                    case .thread:
                        ThreadView(viewModel: appState.currentThreadViewModel)
                            .id(appState.selectedThread?.id)
                    case .diff:
                        DiffViewer(state: appState.currentDiffState)
                            .id(appState.currentWorkspacePath)
                    case .terminal:
                        TerminalOutputView(manager: appState.terminalManager)
                    case .skills:
                        SkillsPanelView()
                    }
                } else {
                    EmptyWorkspacePlaceholder()
                }
            }

            if appState.selectedThread != nil {
                WorkbenchStatusBar(
                    meteringState: appState.currentThreadViewModel.meteringState,
                    gateState: appState.currentGateState
                )
            }
        }
    }
}

// MARK: - Empty Workspace Placeholder

struct EmptyWorkspacePlaceholder: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 48))
                .foregroundStyle(Color.adOrange)

            VStack(spacing: 4) {
                Text("Adventurers Agent Harness")
                    .font(.title3.bold())
                    .foregroundStyle(Color.adTextPrimary)

                Text("The model proposes. The harness certifies.")
                    .font(.caption)
                    .foregroundStyle(Color.adTextSecondary)
            }

            Button {
                appState.createThread()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("New Thread")
                }
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .foregroundStyle(Color.adTextPrimary)
                .liquidGlassCapsule(strokeOpacity: 0.3)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Inspector Panel (Trailing)

struct InspectorPanel: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Certification Pipeline Status
                InspectorCard(title: "Gate Certification", icon: "shield.fill") {
                    VStack(alignment: .leading, spacing: 6) {
                        GateStatusRow(name: "SyntaxGate", status: "Passed", icon: "checkmark.circle.fill", color: Color.adSuccess)
                        GateStatusRow(name: "RepeatGate", status: "Passed", icon: "checkmark.circle.fill", color: Color.adSuccess)
                        GateStatusRow(name: "CompilationGate", status: "Evaluating", icon: "arrow.triangle.2.circlepath", color: Color.adOrange)
                        GateStatusRow(name: "MemoryGate", status: "Pending", icon: "clock.fill", color: Color.adTextTertiary)
                        GateStatusRow(name: "ObjectiveGate", status: "Pending", icon: "lock.fill", color: Color.adTextTertiary)
                    }
                }

                // Task Contract & Metering Budget
                let metering = appState.currentThreadViewModel.meteringState
                InspectorCard(title: "Task Budget & Metering", icon: "chart.bar.xaxis") {
                    VStack(alignment: .leading, spacing: 6) {
                        ContractRow(label: "Turns Executed", value: "\(metering.totalTurnsCount) / 15")
                        ContractRow(label: "Throughput (TPS)", value: metering.formattedLiveTPS)
                        ContractRow(label: "First Token Latency", value: metering.formattedLiveTTFT)
                        ContractRow(label: "Context Tokens", value: "\(metering.estimatedContextTokens) / \(metering.contextWindowLimit)")
                        ContractRow(label: "Cumulative Spend", value: metering.formattedCumulativeCost)
                    }
                }

                // Active Capabilities
                InspectorCard(title: "Capabilities", icon: "wrench.fill") {
                    VStack(alignment: .leading, spacing: 6) {
                        ToolCapabilityRow(name: "AST Parser", risk: "Low", color: Color.adSuccess)
                        ToolCapabilityRow(name: "Worktree Engine", risk: "Med", color: Color.adWarning)
                        ToolCapabilityRow(name: "Bash Runner", risk: "High", color: Color.adOrange)
                    }
                }
            }
            .padding(14)
        }
        .background(Color.adNavy)
        .navigationTitle("Inspector")
    }
}

// MARK: - Inspector Components

struct InspectorCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(Color.adOrange)

                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.adTextTertiary)
                    .textCase(.uppercase)
            }

            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.adElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct GateStatusRow: View {
    let name: String
    let status: String
    let icon: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)

            Text(name)
                .font(.system(size: 11))
                .foregroundStyle(Color.adTextPrimary)

            Spacer()

            Text(status)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(color)
        }
    }
}

struct ContractRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.adTextSecondary)

            Spacer()

            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.adTextPrimary)
        }
    }
}

struct ToolCapabilityRow: View {
    let name: String
    let risk: String
    let color: Color

    var body: some View {
        HStack {
            Text(name)
                .font(.system(size: 11))
                .foregroundStyle(Color.adTextPrimary)

            Spacer()

            Text(risk)
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(color.opacity(0.15))
                .foregroundStyle(color)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Spotlight / Command Palette Modal

struct CommandPaletteModal: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @State private var query: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(Color.adOrange)

                TextField("Type a command or jump to thread...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .onSubmit {
                        dismiss()
                    }

                Button {
                    dismiss()
                } label: {
                    Text("ESC")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.adElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(Color.adTextTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(Color.adElevated)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    CommandItemRow(title: "Settings & LLM Providers", subtitle: "Configure API keys, OpenCode, GLM, and gateways", icon: "gearshape", shortcut: "⌘,") {
                        dismiss()
                        openSettings()
                    }

                    CommandItemRow(title: "New Agent Thread", subtitle: "Start a fresh task session", icon: "square.and.pencil", shortcut: "⌘N") {
                        appState.createThread()
                        dismiss()
                    }

                    CommandItemRow(title: "Switch to Diffs View", subtitle: "Review changes proposed by agent", icon: "arrow.triangle.branch", shortcut: "⌘2") {
                        appState.activeTab = .diff
                        dismiss()
                    }

                    CommandItemRow(title: "Open Terminal Logs", subtitle: "Inspect bash execution output", icon: "terminal", shortcut: "⌘3") {
                        appState.activeTab = .terminal
                        dismiss()
                    }

                    CommandItemRow(title: "Toggle Inspector", subtitle: "View gate certification breakdown", icon: "sidebar.right", shortcut: "⌘I") {
                        appState.toggleInspector()
                        dismiss()
                    }
                }
                .padding(10)
            }
        }
        .frame(width: 520, height: 320)
        .background(Color.adBackground)
    }
}

struct CommandItemRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let shortcut: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.adOrange)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.adTextPrimary)

                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.adTextTertiary)
                }

                Spacer()

                Text(shortcut)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.adElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(Color.adTextSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Keyboard Commands

struct AgentCommands: Commands {
    let appState: AppState

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates...") {
                AppUpdateManager.shared.checkForUpdates(silent: false)
            }
        }

        CommandGroup(replacing: .newItem) {
            Button("New Thread") {
                appState.createThread(workingDirectory: appState.activeWorkingDirectory())
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Open Project / Set Workspace...") {
                appState.chooseAndSetWorkingDirectory()
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Spotlight Search") {
                appState.showsCommandPalette = true
            }
            .keyboardShortcut("k", modifiers: .command)
        }

        CommandGroup(after: .toolbar) {
            Button("Toggle Sidebar") {
                appState.toggleSidebar()
            }
            .keyboardShortcut("b", modifiers: .command)

            Button("Toggle Inspector") {
                appState.toggleInspector()
            }
            .keyboardShortcut("i", modifiers: .command)

            Divider()

            Button("Switch to Thread Tab") {
                appState.activeTab = .thread
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Switch to Diffs Tab") {
                appState.activeTab = .diff
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("Switch to Terminal Tab") {
                appState.activeTab = .terminal
            }
            .keyboardShortcut("3", modifiers: .command)

            Button("Switch to Skills Tab") {
                appState.activeTab = .skills
            }
            .keyboardShortcut("4", modifiers: .command)
        }

        CommandMenu("Run") {
            Button("Pause / Resume Execution") {
                if let selectedID = appState.selectedThreadID,
                   let vm = appState.threadViewModels[selectedID] {
                    vm.togglePause(terminalManager: appState.terminalManager)
                }
            }
            .keyboardShortcut(.space, modifiers: [.option])

            Button("Stop Active Run") {
                if let selectedID = appState.selectedThreadID,
                   let vm = appState.threadViewModels[selectedID] {
                    vm.stopRun(terminalManager: appState.terminalManager)
                }
            }
            .keyboardShortcut(".", modifiers: [.command])

            Divider()

            Button("Clear Queued Prompts") {
                if let selectedID = appState.selectedThreadID,
                   let vm = appState.threadViewModels[selectedID] {
                    vm.clearQueuedPrompts()
                }
            }
        }
    }
}

// MARK: - About View

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 56))
                .foregroundStyle(Color.adOrange)
            Text("Adventurers Harness")
                .font(.title2.bold())
                .foregroundStyle(Color.adTextPrimary)
            Text("Swift 6 Native macOS Coding Agent Harness")
                .font(.callout)
                .foregroundStyle(Color.adTextSecondary)
            Text("The model proposes. The harness certifies.")
                .font(.subheadline)
                .foregroundStyle(Color.adTextTertiary)
                .italic()
            Divider()
            Text("Version 1.0.0 • macOS Native")
                .font(.caption)
                .foregroundStyle(Color.adTextSecondary)
        }
        .padding(32)
        .frame(width: 380, height: 320)
        .background(Color.adBackground)
    }
}
