//
//  AdventurersApp.swift
//  Adventurers Harness
//
//  macOS coding agent harness — three-panel workspace for parallel agent threads.
//  Inspired by OpenAI Codex desktop, rebuilt with Swift concurrency and SwiftUI.
//

import SwiftUI

// MARK: - App State

/// Top-level application state managed as an `@Observable` singleton.
/// Drives thread list, selection, inspector visibility, and sidebar presentation.
@Observable
@MainActor
final class AppState {

    // MARK: Thread Management

    /// All open agent threads, keyed by stable ID.
    var threads: [ThreadID: AgentThread] = [:]

    /// Currently selected thread in the sidebar.
    var selectedThreadID: ThreadID?

    /// Monotonically increasing ID generator — no two threads share a value.
    private var nextThreadID: UInt64 = 1

    // MARK: Panel Visibility

    /// Whether the sidebar (thread list) is visible.
    var showsSidebar: Bool = true

    /// Whether the inspector panel (tools / gates) is visible.
    var showsInspector: Bool = false

    // MARK: Computed

    /// The thread currently being viewed, derived from `selectedThreadID`.
    var activeThread: AgentThread? {
        guard let id = selectedThreadID else { return nil }
        return threads[id]
    }

    // MARK: Actions

    /// Create a new agent thread and select it immediately.
    func createThread() {
        let id = ThreadID(rawValue: nextThreadID)
        nextThreadID += 1

        let thread = AgentThread(
            id: id,
            title: "Thread \(id.rawValue)",
            createdAt: .now
        )

        threads[id] = thread
        selectedThreadID = id
    }

    /// Close a thread and update selection to the nearest neighbour.
    func closeThread(_ id: ThreadID) {
        threads.removeValue(forKey: id)

        if selectedThreadID == id {
            let sorted = threads.keys.sorted(by: { $0.rawValue < $1.rawValue })
            selectedThreadID = sorted.last
        }
    }

    /// Toggle the inspector panel on the trailing edge.
    func toggleInspector() {
        showsInspector.toggle()
    }
}

// MARK: - Thread Model

/// A stable, hashable identifier for an agent thread.
struct ThreadID: Hashable, Comparable, Sendable {
    let rawValue: UInt64

    static func < (lhs: ThreadID, rhs: ThreadID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A single agent conversation thread.
struct AgentThread: Identifiable, Sendable {
    let id: ThreadID
    var title: String
    let createdAt: Date
    var messages: [ChatMessage] = []
}

/// A single chat message exchanged with the agent.
struct ChatMessage: Identifiable, Sendable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date

    init(role: MessageRole, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = .now
    }
}

/// The role of a chat participant.
enum MessageRole: Sendable {
    case user
    case assistant
    case system
}

// MARK: - App Entry Point

@main
struct AdventurersApp: App {

    @State private var appState = AppState()

    // MARK: Scene Composition

    var body: some Scene {
        // Primary workspace window — opens on launch.
        WindowGroup(id: "workspace") {
            ContentView()
                .environment(appState)
                .frame(minWidth: 960, minHeight: 600)
        }
        .defaultSize(width: 1_440, height: 900)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            AgentCommands(appState: appState)
        }

        // Settings scene — accessible via Cmd+, or the app menu.
        Settings {
            SettingsView()
                .environment(appState)
        }

        // About window with custom branding.
        Window("About Adventurers Harness", id: "about-window") {
            AboutView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

// MARK: - Primary Content View

/// Root three-panel layout using `NavigationSplitView`.
struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            ThreadContentView()
        } detail: {
            DetailPlaceholderView()
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360, for: .sidebar)
        .navigationSplitViewColumnWidth(min: 300, ideal: 480, for: .content)
        .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
        .inspector(isPresented: Binding(
            get: { appState.showsInspector },
            set: { _ in appState.toggleInspector() }
        )) {
            InspectorView()
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        appState.showsSidebar.toggle()
                    }
                } label: {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                }
                .help("Toggle sidebar")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appState.createThread()
                } label: {
                    Label("New Thread", systemImage: "plus.message")
                }
                .help("New agent thread")

                Button {
                    appState.toggleInspector()
                } label: {
                    Label("Toggle Inspector", systemImage: "sidebar.right")
                }
                .help("Toggle inspector panel")
            }
        }
    }
}

// MARK: - Sidebar (Thread List)

/// Left panel listing all open agent threads.
struct SidebarView: View {
    @Environment(AppState.self) private var appState

    private var sortedThreads: [AgentThread] {
        appState.threads.values.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        List(
            selection: Binding(
                get: { appState.selectedThreadID },
                set: { appState.selectedThreadID = $0 }
            )
        ) {
            Section {
                ForEach(sortedThreads) { thread in
                    ThreadRow(thread: thread)
                        .tag(thread.id)
                }
            } header: {
                Label("Threads", systemImage: "bubble.left.and.bubble.right")
                    .font(.headline)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Adventurers")
        .toolbar {
            ToolbarItem {
                Button {
                    appState.createThread()
                } label: {
                    Image(systemName: "plus")
                }
                .help("New thread")
            }
        }
    }
}

// MARK: - Thread Row

/// A single row in the sidebar thread list.
struct ThreadRow: View {
    let thread: AgentThread

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(thread.title)
                .font(.body)
                .lineLimit(1)

            Text(thread.createdAt, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Thread Content View

/// Center panel — displays the chat thread for the selected agent.
struct ThreadContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let thread = appState.activeThread {
            ChatView(thread: thread)
        } else {
            EmptyStateView()
        }
    }
}

// MARK: - Chat View

/// Renders the message list and composer for a single thread.
struct ChatView: View {
    let thread: AgentThread

    var body: some View {
        VStack(spacing: 0) {
            // Message list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if thread.messages.isEmpty {
                            WelcomeMessage()
                        } else {
                            ForEach(thread.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                }
                .onChange(of: thread.messages.count) { _, _ in
                    if let last = thread.messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Composer bar
            ComposerBar()
                .padding(12)
        }
        .navigationTitle(thread.title)
    }
}

// MARK: - Message Bubble

/// A single chat message rendered as a card-style bubble.
struct MessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }
    private var isSystem: Bool { message.role == .system }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isUser { Spacer(minLength: 60) }

            if isSystem {
                SystemBadge()
            } else {
                VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: isUser ? "person.fill" : "cpu")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(isUser ? "You" : "Agent")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }

                    Text(message.content)
                        .textSelection(.enabled)
                        .padding(12)
                        .background(messageBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var messageBackground: some View {
        if isUser {
            Color.accentColor.opacity(0.15)
        } else {
            Color(nsColor: .controlBackgroundColor)
        }
    }
}

// MARK: - System Badge

/// Inline badge for system messages (tool calls, gate approvals, etc.).
struct SystemBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "gearshape.fill")
                .font(.caption)

            Text("System event")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - Welcome Message

/// Displayed when a thread has no messages yet.
struct WelcomeMessage: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Ready to begin")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Type a message or command below to start a new agent session.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 120)
    }
}

// MARK: - Empty State

/// Displayed when no thread is selected.
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)

            VStack(spacing: 8) {
                Text("No Thread Selected")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Select a thread from the sidebar, or create a new one.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Composer Bar

/// Input bar at the bottom of the chat view.
struct ComposerBar: View {
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message the agent\u{2026}", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
                .focused($isInputFocused)
                .onSubmit {
                    sendMessage()
                }

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
            }
            .buttonStyle(.plain)
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // TODO: Forward to agent pipeline.
        inputText = ""
        isInputFocused = true
    }
}

// MARK: - Inspector View

/// Right panel showing tool calls, gate approvals, and metadata.
struct InspectorView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Label("Inspector", systemImage: "sidebar.right")
                    .font(.headline)

                Spacer()

                Button {
                    appState.toggleInspector()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            if let thread = appState.activeThread {
                InspectorContent(thread: thread)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "info.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)

                    Text("Select a thread to view details")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Inspector Content

/// Populated inspector showing tool calls and gates for the active thread.
struct InspectorContent: View {
    let thread: AgentThread

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Thread Info
                InspectorSection(title: "Thread Info", icon: "info.circle") {
                    InspectorRow(label: "ID", value: "\(thread.id.rawValue)")
                    InspectorRow(label: "Created", value: thread.createdAt.formatted())
                    InspectorRow(label: "Messages", value: "\(thread.messages.count)")
                }

                // Tool Calls (placeholder)
                InspectorSection(title: "Tool Calls", icon: "wrench.and.screwdriver") {
                    if thread.messages.isEmpty {
                        Text("No tool calls yet")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                // Gate Approvals (placeholder)
                InspectorSection(title: "Gate Approvals", icon: "lock.shield") {
                    Text("No pending gates")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                // Agent Status (placeholder)
                InspectorSection(title: "Agent Status", icon: "cpu") {
                    InspectorRow(label: "Status", value: "Idle")
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Inspector Section

/// A collapsible section within the inspector panel.
struct InspectorSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(.tint)

                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    content
                }
                .padding(.leading, 20)
            }
        }
    }
}

// MARK: - Inspector Row

/// A key-value row inside the inspector.
struct InspectorRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)

            Text(value)
                .font(.caption)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Settings View

/// Application settings accessible via Cmd+,.
struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
        }
        .frame(width: 450, height: 300)
        .padding()
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Open last thread on launch", isOn: .constant(true))
                Toggle("Restore panel layout", isOn: .constant(true))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Appearance Settings

struct AppearanceSettingsView: View {
    var body: some View {
        Form {
            Section("Theme") {
                Toggle("Use system appearance", isOn: .constant(false))

                Picker("Accent Color", selection: .constant("Adventurers Orange")) {
                    Text("Adventurers Orange").tag("Adventurers Orange")
                    Text("System Blue").tag("System Blue")
                    Text("Purple").tag("Purple")
                    Text("Green").tag("Green")
                }
            }

            Section("Chat") {
                Toggle("Show timestamps", isOn: .constant(true))
                Toggle("Compact messages", isOn: .constant(false))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About View

/// Custom About window with Adventurers branding.
struct AboutView: View {
    private let appVersion: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }()

    private let buildNumber: String = {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }()

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 32)

            // App icon / logo
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.42, blue: 0.21),   // #FF6B35
                                Color(red: 0.95, green: 0.35, blue: 0.15),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)

                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white)
            }

            Spacer(minLength: 16)

            Text("Adventurers Harness")
                .font(.title2)
                .fontWeight(.bold)

            Text("Version \(appVersion) (\(buildNumber))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Text("A macOS coding agent workspace.\nBuild parallel agent threads with\nfull tool visibility and gate controls.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Spacer(minLength: 20)

            Divider()

            HStack(spacing: 20) {
                Link("Documentation", destination: URL(string: "https://github.com/bytecats/adventurers-harness")!)
                    .font(.callout)

                Link("Report an Issue", destination: URL(string: "https://github.com/bytecats/adventurers-harness/issues")!)
                    .font(.callout)
            }
            .padding(.vertical, 12)

            Text("\u{00A9} 2026 ByteCats. All rights reserved.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(width: 360, height: 440)
    }
}

// MARK: - Menu Bar Commands

/// Custom menu commands for the app.
struct AgentCommands: Commands {
    let appState: AppState

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Thread") {
                appState.createThread()
            }
            .keyboardShortcut("n", modifiers: .command)

            Divider()

            Button("Toggle Inspector") {
                appState.toggleInspector()
            }
            .keyboardShortcut("i", modifiers: .command)
        }

        CommandGroup(after: .toolbar) {
            Button("Toggle Sidebar") {
                withAnimation(.spring(response: 0.3)) {
                    appState.showsSidebar.toggle()
                }
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
        }

        // Custom About menu item.
        CommandGroup(replacing: .appInfo) {
            Button("About Adventurers Harness") {
                NSApplication.shared.keyWindow?.contentViewController?
                    .presentedViewControllers?.forEach {
                        $0.dismiss(nil)
                    }
                NSApp.sendAction(Selector(("showSettingsWindow")), to: nil, from: nil)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Main Window") {
    ContentView()
        .environment(AppState())
}
#endif
