// AdventurersHarness - Settings
// Comprehensive macOS settings window with sidebar-style tabs
// macOS 15+ · @Observable · Swift 6 strict concurrency

import SwiftUI
import Observation

// MARK: - Settings Model

/// Central settings model persisted to `~/Library/Application Support/AdventurersHarness/settings.json`.
///
/// Uses `@Observable` for SwiftUI reactivity and `Codable` for disk persistence.
/// All properties are `@ObservationIgnored` for defaults tracking where needed.
@Observable
@MainActor
public final class SettingsModel {
    // MARK: General

    /// Whether the app opens the last project on launch.
    public var openLastProjectOnLaunch = true
    /// Default shell used for tool execution.
    public var defaultShell = "/bin/zsh"
    /// Shell arguments passed on launch.
    public var defaultShellArgs = ["-l"]
    /// Application support data directory path.
    public var dataDirectory = "~/.adventurers"
    /// Automatically compact conversation context when token usage exceeds threshold.
    public var autoCompact = true
    /// Token threshold (percentage) that triggers auto-compaction.
    public var autoCompactThreshold = 80
    /// Check for updates on launch.
    public var checkUpdatesOnLaunch = true

    // MARK: LLM Provider

    /// Active LLM provider.
    public var activeProvider: ProviderType = .openai
    /// Provider-specific API key.
    public var apiKey = ""
    /// Selected model identifier.
    public var selectedModel = "gpt-4o"
    /// Sampling temperature (0.0 – 2.0).
    public var temperature: Double = 0.7
    /// Maximum tokens per completion.
    public var maxTokens: Int = 4096
    /// Base URL override (used by .local provider).
    public var baseURL = ""
    /// Request timeout in seconds.
    public var requestTimeout: Double = 120

    /// Available models per provider.
    public static let modelsByProvider: [ProviderType: [String]] = [
        .openai: ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "o1", "o1-mini", "o3-mini"],
        .anthropic: ["claude-sonnet-4-20250514", "claude-3-5-haiku-20241022", "claude-opus-4-20250514"],
        .local: ["custom"],
    ]

    // MARK: Agents

    /// Agent personality style.
    public var agentPersonality: PersonalityStyle = .terse
    /// Maximum agent loop rounds before budget exhaustion.
    public var maxRounds: Int = 4
    /// Which gates are required to pass before task completion.
    public var requiredGates: Set<String> = ["syntax", "repeat"]
    /// Available gate names for toggling.
    public static let availableGates = ["syntax", "repeat", "compilation"]

    // MARK: Tools

    /// Per-tool enabled state.
    public var enabledTools: Set<String> = ["bash", "file", "grep", "glob"]
    /// Available tool definitions.
    public static let availableTools: [(name: String, risk: RiskLevel)] = [
        ("bash", .execute),
        ("file", .write),
        ("grep", .readOnly),
        ("glob", .readOnly),
        ("fetch", .network),
        ("patch", .destructive),
    ]
    /// Bash timeout in seconds.
    public var bashTimeout: Double = 60

    // MARK: Sandbox

    /// Allowed file-access paths (glob patterns).
    public var fileAccessPaths: [String] = ["**/*"]
    /// Blocked file-access paths.
    public var blockedPaths: [String] = ["~/.ssh/*", "~/.aws/*"]
    /// Network access mode.
    public var networkAccess: NetworkAccess = .restricted
    /// Blocked commands (shell blocklist).
    public var commandBlocklist: [String] = ["rm -rf /", "sudo rm -rf"]
    /// Allowed commands (empty = all non-blocked allowed).
    public var commandAllowlist: [String] = []

    // MARK: Appearance

    /// App colour theme.
    public var colorScheme: AppColorScheme = .system
    /// Accent colour.
    public var accentColor: AccentColorChoice = .blue
    /// UI font size.
    public var fontSize: Double = 13
    /// Code / monospace font name.
    public var codeFont = "SF Mono"
    /// Enable compact mode (denser spacing).
    public var compactMode = false

    // MARK: Keyboard

    /// Custom keybindings (action → shortcut string).
    public var keybindings: [String: String] = [
        "newTask": "⌘N",
        "toggleSidebar": "⌘S",
        "focusPrompt": "⌘L",
        "cancelTask": "⌘.",
        "showSettings": "⌘,",
    ]

    // MARK: Persistence

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// File URL for persisted settings.
    private var settingsFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AdventurersHarness")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }

    public init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
    }

    // MARK: – Persistence

    /// Load settings from disk, falling back to defaults.
    public func load() {
        guard FileManager.default.fileExists(atPath: settingsFileURL.path),
              let data = try? Data(contentsOf: settingsFileURL),
              let decoded = try? decoder.decode(PersistedSettings.self, from: data) else { return }
        apply(decoded)
    }

    /// Write current settings to disk.
    public func save() {
        let persisted = snapshot()
        guard let data = try? encoder.encode(persisted) else { return }
        try? data.write(to: settingsFileURL, options: .atomic)
    }

    /// Reset every setting to its default value.
    public func resetToDefaults() {
        let fresh = SettingsModel()
        apply(fresh.snapshot())
    }

    /// Generate a `HarnessConfig` from the current settings.
    public func harnessConfig() -> HarnessConfig {
        HarnessConfig(
            llm: LLMConfig(
                provider: activeProvider.rawValue,
                model: selectedModel,
                temperature: temperature,
                maxTokens: maxTokens,
                baseURL: baseURL.isEmpty ? nil : baseURL,
                apiKey: apiKey.isEmpty ? nil : apiKey
            ),
            maxRounds: maxRounds,
            requiredGates: Array(requiredGates),
            enabledTools: Array(enabledTools),
            shell: .init(path: defaultShell, args: defaultShellArgs),
            autoCompact: autoCompact
        )
    }

    // MARK: – Private helpers

    private func snapshot() -> PersistedSettings {
        PersistedSettings(
            openLastProjectOnLaunch: openLastProjectOnLaunch,
            defaultShell: defaultShell,
            defaultShellArgs: defaultShellArgs,
            dataDirectory: dataDirectory,
            autoCompact: autoCompact,
            autoCompactThreshold: autoCompactThreshold,
            checkUpdatesOnLaunch: checkUpdatesOnLaunch,
            activeProvider: activeProvider,
            apiKey: apiKey,
            selectedModel: selectedModel,
            temperature: temperature,
            maxTokens: maxTokens,
            baseURL: baseURL,
            requestTimeout: requestTimeout,
            agentPersonality: agentPersonality,
            maxRounds: maxRounds,
            requiredGates: requiredGates,
            enabledTools: enabledTools,
            bashTimeout: bashTimeout,
            fileAccessPaths: fileAccessPaths,
            blockedPaths: blockedPaths,
            networkAccess: networkAccess,
            commandBlocklist: commandBlocklist,
            commandAllowlist: commandAllowlist,
            colorScheme: colorScheme,
            accentColor: accentColor,
            fontSize: fontSize,
            codeFont: codeFont,
            compactMode: compactMode,
            keybindings: keybindings
        )
    }

    private func apply(_ p: PersistedSettings) {
        openLastProjectOnLaunch = p.openLastProjectOnLaunch
        defaultShell = p.defaultShell
        defaultShellArgs = p.defaultShellArgs
        dataDirectory = p.dataDirectory
        autoCompact = p.autoCompact
        autoCompactThreshold = p.autoCompactThreshold
        checkUpdatesOnLaunch = p.checkUpdatesOnLaunch
        activeProvider = p.activeProvider
        apiKey = p.apiKey
        selectedModel = p.selectedModel
        temperature = p.temperature
        maxTokens = p.maxTokens
        baseURL = p.baseURL
        requestTimeout = p.requestTimeout
        agentPersonality = p.agentPersonality
        maxRounds = p.maxRounds
        requiredGates = p.requiredGates
        enabledTools = p.enabledTools
        bashTimeout = p.bashTimeout
        fileAccessPaths = p.fileAccessPaths
        blockedPaths = p.blockedPaths
        networkAccess = p.networkAccess
        commandBlocklist = p.commandBlocklist
        commandAllowlist = p.commandAllowlist
        colorScheme = p.colorScheme
        accentColor = p.accentColor
        fontSize = p.fontSize
        codeFont = p.codeFont
        compactMode = p.compactMode
        keybindings = p.keybindings
    }
}

// MARK: - Persisted Settings (Codable mirror)

/// Codable value-type mirror of `SettingsModel` for JSON serialisation.
struct PersistedSettings: Codable {
    var openLastProjectOnLaunch: Bool
    var defaultShell: String
    var defaultShellArgs: [String]
    var dataDirectory: String
    var autoCompact: Bool
    var autoCompactThreshold: Int
    var checkUpdatesOnLaunch: Bool
    var activeProvider: ProviderType
    var apiKey: String
    var selectedModel: String
    var temperature: Double
    var maxTokens: Int
    var baseURL: String
    var requestTimeout: Double
    var agentPersonality: PersonalityStyle
    var maxRounds: Int
    var requiredGates: Set<String>
    var enabledTools: Set<String>
    var bashTimeout: Double
    var fileAccessPaths: [String]
    var blockedPaths: [String]
    var networkAccess: NetworkAccess
    var commandBlocklist: [String]
    var commandAllowlist: [String]
    var colorScheme: AppColorScheme
    var accentColor: AccentColorChoice
    var fontSize: Double
    var codeFont: String
    var compactMode: Bool
    var keybindings: [String: String]
}

// MARK: - Settings Enums

/// Supported LLM providers.
public enum ProviderType: String, CaseIterable, Sendable, Codable {
    case openai = "OpenAI"
    case anthropic = "Anthropic"
    case local = "Local"

    /// SF Symbol name for the provider icon.
    public var icon: String {
        switch self {
        case .openai: "brain.head.profile"
        case .anthropic: "cube.transparent"
        case .local: "desktopcomputer"
        }
    }
}

/// Agent communication style.
public enum PersonalityStyle: String, CaseIterable, Sendable, Codable {
    case terse = "Terse"
    case conversational = "Conversational"

    public var description: String {
        switch self {
        case .terse: "Short, direct responses. Minimal explanation."
        case .conversational: "Full sentences, explanations, and context."
        }
    }
}

/// Network access policy for the sandbox.
public enum NetworkAccess: String, CaseIterable, Sendable, Codable {
    case open = "Open"
    case restricted = "Restricted"
    case offline = "Offline"

    public var description: String {
        switch self {
        case .open: "Allow all network requests without restriction."
        case .restricted: "Only allow requests to approved domains."
        case .offline: "Block all network access."
        }
    }
}

/// App colour scheme preference.
public enum AppColorScheme: String, CaseIterable, Sendable, Codable {
    case light = "Light"
    case dark = "Dark"
    case system = "System"
}

/// Accent colour choices.
public enum AccentColorChoice: String, CaseIterable, Sendable, Codable {
    case blue, purple, pink, red, orange, yellow, green, teal, indigo, gray

    public var color: Color {
        switch self {
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .indigo: .indigo
        case .gray: .gray
        }
    }
}

// MARK: - Settings View

/// Main settings window with sidebar-style tabbed interface.
///
/// Renders eight tabs (General, LLM Provider, Agents, Tools, Sandbox,
/// Appearance, Keyboard, About) in a `TabView` with `.sidebarAdaptable` style.
public struct SettingsView: View {
    @Bindable var model: SettingsModel
    @State private var searchText = ""

    public init(model: SettingsModel) {
        self.model = model
    }

    public var body: some View {
        TabView {
            GeneralSettingsTab(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            LLMProviderSettingsTab(model: model)
                .tabItem { Label("LLM Provider", systemImage: "brain.head.profile") }
                .tag(SettingsTab.llmProvider)

            AgentSettingsTab(model: model)
                .tabItem { Label("Agents", systemImage: "person.2.fill") }
                .tag(SettingsTab.agents)

            ToolSettingsTab(model: model)
                .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
                .tag(SettingsTab.tools)

            SandboxSettingsTab(model: model)
                .tabItem { Label("Sandbox", systemImage: "lock.shield") }
                .tag(SettingsTab.sandbox)

            AppearanceSettingsTab(model: model)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
                .tag(SettingsTab.appearance)

            KeyboardSettingsTab(model: model)
                .tabItem { Label("Keyboard", systemImage: "keyboard") }
                .tag(SettingsTab.keyboard)

            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .tabViewStyle(.sidebarAdaptable)
        .frame(minWidth: 680, minHeight: 480)
        .searchable(text: $searchText, prompt: "Search settings…")
    }
}

// MARK: - Settings Tab Identifier

private enum SettingsTab: String, CaseIterable {
    case general, llmProvider, agents, tools, sandbox, appearance, keyboard, about
}

// MARK: - General Settings Tab

struct GeneralSettingsTab: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            SectionHeader(
                title: "General",
                subtitle: "Startup behaviour, shell, and data paths."
            )

            StartupSection(model: model)
            ShellSection(model: model)
            DataSection(model: model)
            MaintenanceSection(model: model)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Startup Section

private struct StartupSection: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Section("Startup") {
            Toggle("Open last project on launch", isOn: $model.openLastProjectOnLaunch)
            Toggle("Check for updates on launch", isOn: $model.checkUpdatesOnLaunch)
        }
    }
}

// MARK: - Shell Section

private struct ShellSection: View {
    @Bindable var model: SettingsModel

    private let shells = ["/bin/zsh", "/bin/bash", "/bin/fish", "/usr/bin/env"]

    var body: some View {
        Section("Shell") {
            Picker("Default shell", selection: $model.defaultShell) {
                ForEach(shells, id: \.self) { shell in
                    Text(shell).tag(shell)
                }
            }

            HStack {
                Text("Shell arguments")
                Spacer()
                TextField("-l", text: Binding(
                    get: { model.defaultShellArgs.joined(separator: " ") },
                    set: { model.defaultShellArgs = $0.split(separator: " ").map(String.init) }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
            }
        }
    }
}

// MARK: - Data Section

private struct DataSection: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Section("Data Directory") {
            HStack {
                Text("Path")
                Spacer()
                TextField("~/.adventurers", text: $model.dataDirectory)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)

                Button("Choose…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        model.dataDirectory = url.path
                    }
                }
                .buttonStyle(.borderless)
            }

            HStack {
                Text("Contents")
                Spacer()
                Text(model.dataDirectory)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }
}

// MARK: - Maintenance Section

private struct MaintenanceSection: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Section("Maintenance") {
            Toggle("Auto-compact conversations", isOn: $model.autoCompact)

            if model.autoCompact {
                SliderStepperView(
                    title: "Compact threshold",
                    value: $model.autoCompactThreshold,
                    in: 50...100,
                    step: 5,
                    unit: "%",
                    help: "Percentage of context window that triggers auto-compaction."
                )
            }
        }
    }
}

// MARK: - LLM Provider Settings Tab

struct LLMProviderSettingsTab: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            SectionHeader(
                title: "LLM Provider",
                subtitle: "Configure the language model backend, credentials, and request parameters."
            )

            ProviderSelectionSection(model: model)
            CredentialsSection(model: model)
            ModelSection(model: model)
            ParametersSection(model: model)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Provider Selection

private struct ProviderSelectionSection: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Section("Provider") {
            Picker("Provider", selection: $model.activeProvider) {
                ForEach(ProviderType.allCases, id: \.self) { provider in
                    Label(provider.rawValue, systemImage: provider.icon).tag(provider)
                }
            }
            .pickerStyle(.radioGroup)
        }
    }
}

// MARK: - Credentials

private struct CredentialsSection: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Section("Credentials") {
            APIKeyField(
                title: "API Key",
                key: $model.apiKey,
                placeholder: model.activeProvider == .local ? "Not required" : "sk-…"
            )

            if model.activeProvider == .local {
                HStack {
                    Text("Base URL")
                    Spacer()
                    TextField("http://localhost:11434/v1", text: $model.baseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 350)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.2), value: model.activeProvider)
            }

            HStack {
                Text("Timeout (seconds)")
                Spacer()
                SliderStepperView(
                    title: "",
                    value: $model.requestTimeout,
                    in: 10...300,
                    step: 10,
                    unit: "s",
                    help: "HTTP request timeout for LLM API calls."
                )
                .labelsHidden()
            }
        }
    }
}

// MARK: - Model Section

private struct ModelSection: View {
    @Bindable var model: SettingsModel

    private var availableModels: [String] {
        SettingsModel.modelsByProvider[model.activeProvider] ?? ["custom"]
    }

    var body: some View {
        Section("Model") {
            Picker("Model", selection: $model.selectedModel) {
                ForEach(availableModels, id: \.self) { model in
                    Text(model).tag(model)
                }
            }

            if model.activeProvider == .local {
                HStack {
                    Text("Custom model ID")
                    Spacer()
                    TextField("model-name", text: $model.selectedModel)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)
                }
            }
        }
    }
}

// MARK: - Parameters

private struct ParametersSection: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Section("Parameters") {
            SliderStepperView(
                title: "Temperature",
                value: $model.temperature,
                in: 0.0...2.0,
                step: 0.05,
                unit: "",
                help: "Lower values produce more deterministic output; higher values increase randomness."
            )

            SliderStepperView(
                title: "Max tokens",
                value: Binding(
                    get: { Double(model.maxTokens) },
                    set: { model.maxTokens = Int($0) }
                ),
                in: 256...131072,
                step: 256,
                unit: "",
                help: "Maximum number of tokens in the model's completion."
            )
        }
    }
}

// MARK: - Agents Settings Tab

struct AgentSettingsTab: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            SectionHeader(
                title: "Agents",
                subtitle: "Configure agent personality, loop budget, and certification gates."
            )

            PersonalitySection(model: model)
            LoopBudgetSection(model: model)
            GatesSection(model: model)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Personality

private struct PersonalitySection: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Section("Personality") {
            Picker("Agent style", selection: $model.agentPersonality) {
                ForEach(PersonalityStyle.allCases, id: \.self) { style in
                    VStack(alignment: .leading) {
                        Text(style.rawValue)
                        Text(style.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(style)
                }
            }
            .pickerStyle(.radioGroup)
        }
    }
}

// MARK: - Loop Budget

private struct LoopBudgetSection: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Section("Loop Budget") {
            SliderStepperView(
                title: "Maximum rounds",
                value: Binding(
                    get: { Double(model.maxRounds) },
                    set: { model.maxRounds = Int($0) }
                ),
                in: 1...20,
                step: 1,
                unit: "",
                help: "Number of propose→gate→repair cycles before the harness gives up."
            )
        }
    }
}

// MARK: - Gates

private struct GatesSection: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Section("Certification Gates") {
            Text("Required gates must pass before a task is marked complete.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(SettingsModel.availableGates, id: \.self) { gate in
                Toggle(isOn: Binding(
                    get: { model.requiredGates.contains(gate) },
                    set: { _ in toggleGate(gate) }
                )) {
                    HStack {
                        Image(systemName: model.requiredGates.contains(gate) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(model.requiredGates.contains(gate) ? .green : .secondary)
                        Text(gate.capitalized)
                        Spacer()
                        gateDetail(for: gate)
                    }
                }
            }
        }
    }

    private func toggleGate(_ gate: String) {
        if model.requiredGates.contains(gate) {
            model.requiredGates.remove(gate)
        } else {
            model.requiredGates.insert(gate)
        }
    }

    @ViewBuilder
    private func gateDetail(for gate: String) -> some View {
        switch gate {
        case "syntax":
            Text("Brace & paren balance")
                .font(.caption)
                .foregroundStyle(.secondary)
        case "repeat":
            Text("Rejects duplicate submissions")
                .font(.caption)
                .foregroundStyle(.secondary)
        case "compilation":
            Text("Compiles output code")
                .font(.caption)
                .foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }
}

// MARK: - Tools Settings Tab

struct ToolSettingsTab: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            SectionHeader(
                title: "Tools",
                subtitle: "Enable or disable individual tools and configure execution limits."
            )

            ToolToggleSection(model: model)
            BashTimeoutSection(model: model)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Tool Toggle

private struct ToolToggleSection: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Section("Available Tools") {
            ForEach(SettingsModel.availableTools, id: \.name) { tool in
                Toggle(isOn: Binding(
                    get: { model.enabledTools.contains(tool.name) },
                    set: { _ in toggleTool(tool.name) }
                )) {
                    HStack {
                        Image(systemName: model.enabledTools.contains(tool.name) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(model.enabledTools.contains(tool.name) ? .green : .secondary)
                        Text(tool.name)
                        Spacer()
                        RiskBadge(level: tool.risk)
                    }
                }
            }
        }
    }

    private func toggleTool(_ name: String) {
        if model.enabledTools.contains(name) {
            model.enabledTools.remove(name)
        } else {
            model.enabledTools.insert(name)
        }
    }
}

// MARK: - Bash Timeout

private struct BashTimeoutSection: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Section("Execution Limits") {
            SliderStepperView(
                title: "Bash timeout",
                value: $model.bashTimeout,
                in: 5...600,
                step: 5,
                unit: "s",
                help: "Maximum runtime for a single bash command before the harness kills it."
            )
        }
    }
}

// MARK: - Risk Badge

/// Small coloured badge indicating the risk level of a tool.
private struct RiskBadge: View {
    let level: RiskLevel

    var body: some View {
        Text(level.rawValue)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor.opacity(0.15), in: Capsule())
            .foregroundStyle(backgroundColor)
    }

    private var backgroundColor: Color {
        switch level {
        case .readOnly: .green
        case .network: .blue
        case .write: .orange
        case .execute: .red
        case .destructive: .purple
        }
    }
}

// MARK: - Sandbox Settings Tab

struct SandboxSettingsTab: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            SectionHeader(
                title: "Sandbox",
                subtitle: "File access, network rules, and command restrictions."
            )

            FileAccessSection(model: model)
            NetworkSection(model: model)
            CommandSection(model: model)
        }
        .formStyle(.grouped)
    }
}

// MARK: - File Access

private struct FileAccessSection: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Section("File Access") {
            EditableTagList(title: "Allowed paths", tags: $model.fileAccessPaths, placeholder: "Add glob pattern…")
            EditableTagList(title: "Blocked paths", tags: $model.blockedPaths, placeholder: "Add glob pattern…")
        }
    }
}

// MARK: - Network

private struct NetworkSection: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Section("Network") {
            Picker("Access policy", selection: $model.networkAccess) {
                ForEach(NetworkAccess.allCases, id: \.self) { access in
                    VStack(alignment: .leading) {
                        Text(access.rawValue)
                        Text(access.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(access)
                }
            }
            .pickerStyle(.radioGroup)
        }
    }
}

// MARK: - Command Restrictions

private struct CommandSection: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Section("Command Restrictions") {
            EditableTagList(title: "Blocklist", tags: $model.commandBlocklist, placeholder: "Add command…")
            EditableTagList(title: "Allowlist", tags: $model.commandAllowlist, placeholder: "Add command…")

            if !model.commandAllowlist.isEmpty {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                    Text("When the allowlist is non-empty, only listed commands are permitted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Appearance Settings Tab

struct AppearanceSettingsTab: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            SectionHeader(
                title: "Appearance",
                subtitle: "Theme, colours, typography, and layout density."
            )

            ThemeSection(model: model)
            ColourSection(model: model)
            TypographySection(model: model)
            LayoutSection(model: model)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Theme

private struct ThemeSection: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Section("Theme") {
            Picker("Colour scheme", selection: $model.colorScheme) {
                ForEach(AppColorScheme.allCases, id: \.self) { scheme in
                    Text(scheme.rawValue).tag(scheme)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

// MARK: - Colour

private struct ColourSection: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Section("Accent Colour") {
            HStack(spacing: 8) {
                ForEach(AccentColorChoice.allCases, id: \.self) { colour in
                    Button {
                        model.accentColor = colour
                    } label: {
                        Circle()
                            .fill(colour.color)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .stroke(.white, lineWidth: model.accentColor == colour ? 3 : 0)
                                    .frame(width: 24, height: 24)
                            )
                            .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(colour.rawValue.capitalized))
                }
            }
        }
    }
}

// MARK: - Typography

private struct TypographySection: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Section("Typography") {
            SliderStepperView(
                title: "Font size",
                value: $model.fontSize,
                in: 10...24,
                step: 1,
                unit: "pt",
                help: "Base font size for the terminal UI."
            )

            HStack {
                Text("Code font")
                Spacer()
                Picker("", selection: $model.codeFont) {
                    ForEach(["SF Mono", "Menlo", "Monaco", "Fira Code", "JetBrains Mono"], id: \.self) {
                        Text($0).tag($0)
                    }
                }
                .frame(width: 180)
            }
        }
    }
}

// MARK: - Layout

private struct LayoutSection: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Section("Layout") {
            Toggle("Compact mode", isOn: $model.compactMode)
            if model.compactMode {
                Text("Reduces spacing and padding for a denser interface.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Keyboard Settings Tab

struct KeyboardSettingsTab: View {
    @Bindable var model: SettingsModel

    private let actions: [(key: String, label: String)] = [
        ("newTask", "New Task"),
        ("toggleSidebar", "Toggle Sidebar"),
        ("focusPrompt", "Focus Prompt"),
        ("cancelTask", "Cancel Task"),
        ("showSettings", "Show Settings"),
    ]

    var body: some View {
        Form {
            SectionHeader(
                title: "Keyboard",
                subtitle: "Customise keyboard shortcuts for common actions."
            )

            Section("Keybindings") {
                ForEach(actions, id: \.key) { action in
                    HStack {
                        Text(action.label)
                        Spacer()
                        ShortcutRecorder(
                            shortcut: Binding(
                                get: { model.keybindings[action.key] ?? "" },
                                set: { model.keybindings[action.key] = $0 }
                            )
                        )
                    }
                }
            }

            Section {
                Button("Reset Keybindings to Defaults") {
                    model.keybindings = [
                        "newTask": "⌘N",
                        "toggleSidebar": "⌘S",
                        "focusPrompt": "⌘L",
                        "cancelTask": "⌘.",
                        "showSettings": "⌘,",
                    ]
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About Settings Tab

struct AboutSettingsTab: View {
    @State private var updateAvailable = false
    @State private var isChecking = false

    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var body: some View {
        Form {
            SectionHeader(
                title: "About Adventurers Harness",
                subtitle: "Version information, credits, and licensing."
            )

            Section("Version") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("\(appVersion) (\(buildNumber))")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Swift")
                    Spacer()
                    Text("6.0")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Minimum macOS")
                    Spacer()
                    Text("15.0 (Sequoia)")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Check for Updates") {
                Button {
                    checkForUpdates()
                } label: {
                    HStack {
                        if isChecking {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: updateAvailable ? "arrow.down.circle.fill" : "checkmark.circle")
                            Text(updateAvailable ? "Update Available" : "Check for Updates")
                        }
                    }
                }
                .disabled(isChecking)
            }

            Section("Credits") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Built with:")
                        .font(.headline)
                    CreditRow(name: "Swift", role: "Language")
                    CreditRow(name: "SwiftUI", role: "Interface")
                    CreditRow(name: "OpenAI Swift", role: "LLM Client")
                    CreditRow(name: "ArgumentParser", role: "CLI Framework")
                    CreditRow(name: "swift-composable-architecture", role: "State Management")
                }
            }

            Section("License") {
                Text("""
                Adventurers Harness is released under the MIT License.

                Copyright © 2025 ByteCats. All rights reserved.

                Permission is hereby granted, free of charge, to any person obtaining a copy \
                of this software and associated documentation files, to deal in the Software \
                without restriction, including without limitation the rights to use, copy, \
                modify, merge, publish, distribute, sublicense, and/or sell copies of the \
                Software.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    private func checkForUpdates() {
        isChecking = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            updateAvailable = false
            isChecking = false
        }
    }
}

// MARK: - Credit Row

private struct CreditRow: View {
    let name: String
    let role: String

    var body: some View {
        HStack {
            Text(name)
                .fontWeight(.medium)
            Spacer()
            Text(role)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Reusable Helper Views

// MARK: - Section Header

/// Consistent header for each settings tab.
struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }
}

// MARK: - API Key Field

/// Secure text entry for API keys with a show/hide toggle.
struct APIKeyField: View {
    let title: String
    @Binding var key: String
    var placeholder: String = "sk-…"
    @State private var isSecure = true

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if isSecure {
                SecureField(placeholder, text: $key)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
            } else {
                TextField(placeholder, text: $key)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
            }
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isSecure.toggle()
                }
            } label: {
                Image(systemName: isSecure ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(isSecure ? "Show API key" : "Hide API key"))
        }
    }
}

// MARK: - Slider + Stepper Combo

/// A label + slider + stepper + unit display for numeric settings.
struct SliderStepperView: View {
    let title: String
    @Binding var value: Double
    var bounds: ClosedRange<Double>
    var step: Double
    var unit: String
    var help: String = ""

    init(
        title: String,
        value: Binding<Double>,
        in bounds: ClosedRange<Double>,
        step: Double,
        unit: String,
        help: String = ""
    ) {
        self.title = title
        self._value = value
        self.bounds = bounds
        self.step = step
        self.unit = unit
        self.help = help
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if !title.isEmpty {
                    Text(title)
                }
                Spacer()
                Text(formattedValue)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 50, alignment: .trailing)
            }
            HStack(spacing: 8) {
                Slider(value: $value, in: bounds, step: step)
                    .accessibilityLabel(Text(title))
                Stepper(value: $value, in: bounds, step: step) { _ in }
                    .labelsHidden()
                    .frame(width: 60)
            }
            if !help.isEmpty {
                Text(help)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var formattedValue: String {
        if step >= 1 {
            return "\(Int(value))\(unit.isEmpty ? "" : " \(unit)")"
        } else {
            return String(format: "%.2f%@", value, unit.isEmpty ? "" : " \(unit)")
        }
    }
}

// MARK: - Shortcut Recorder

/// Placeholder shortcut recorder that captures key combinations.
///
/// In a real implementation this would override `keyDown(with:)` to record
/// modifier + key presses and store the Carbon/CGEvent representation.
struct ShortcutRecorder: View {
    @Binding var shortcut: String
    @State private var isRecording = false

    var body: some View {
        Button {
            isRecording.toggle()
        } label: {
            HStack(spacing: 4) {
                if isRecording {
                    Text("Press keys…")
                        .foregroundStyle(.secondary)
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Text(shortcut.isEmpty ? "Record" : shortcut)
                        .monospaced()
                }
            }
            .frame(minWidth: 80)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isRecording ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Record shortcut for \(shortcut)"))
    }
}

// MARK: - Editable Tag List

/// A list of strings the user can add to and remove from (used for paths, blocklists, etc.).
struct EditableTagList: View {
    let title: String
    @Binding var tags: [String]
    var placeholder: String = "Add…"
    @State private var newTag = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !title.isEmpty {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                HStack {
                    Text(tag)
                        .font(.callout)
                        .monospaced()
                    Spacer()
                    Button {
                        tags.remove(at: index)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Remove \(tag)"))
                }
                .padding(.vertical, 2)
            }

            HStack {
                TextField(placeholder, text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addTag() }
                Button("Add") { addTag() }
                    .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !tags.contains(trimmed) else { return }
        tags.append(trimmed)
        newTag = ""
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Settings") {
    SettingsView(model: SettingsModel())
        .frame(width: 720, height: 520)
}
#endif
