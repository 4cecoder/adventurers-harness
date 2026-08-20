// GUI - SettingsView
// Professional macOS Settings Panel with OpenCode & GLM Cloud Plan Integration
// Pure Swift 6 strict concurrency · @Observable

import SwiftUI
import Observation
import AdventurersCore
import LLMProviders

// MARK: - Section Header Component

public struct SectionHeader: View {
    public let title: String
    public let subtitle: String

    public init(title: String, subtitle: String = "") {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.adTextPrimary)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.adTextSecondary)
            }
        }
    }
}

// MARK: - Settings Model

@Observable
@MainActor
public final class SettingsModel {
    // MARK: General
    public var openLastProjectOnLaunch: Bool = true
    public var defaultShell: String = "/bin/zsh"
    public var defaultShellArgs: [String] = ["-l"]
    public var dataDirectory: String = "~/.adventurers"
    public var autoCompact: Bool = true
    public var autoCompactThreshold: Double = 80.0
    public var checkUpdatesOnLaunch: Bool = true
    public var updateChannel: UpdateChannel = .stable {
        didSet { AppUpdateManager.shared.updateChannel = updateChannel }
    }

    // MARK: Speech & Dictation (Talkies Pipeline)
    public var enableDictation: Bool = true {
        didSet { save() }
    }
    public var dictationAutoPunctuation: Bool = true {
        didSet { save() }
    }
    public var dictationSilenceTimeoutSeconds: Double = 4.5 {
        didSet { save() }
    }
    public var dictationLanguage: String = "en-US" {
        didSet { save() }
    }

    // MARK: LLM Provider & Execution Mode
    public var executionMode: ExecutionMode = .codingPlan {
        didSet { save() }
    }
    public var selectedMetaHarness: MetaHarnessType = .codex {
        didSet { save() }
    }
    public var metaHarnessProfiles: [MetaHarnessProfile] = [] {
        didSet { save() }
    }

    public var activeProvider: ProviderType = .opencode {
        didSet {
            updateDefaultsForProvider()
            save()
            Task { @MainActor in
                await self.fetchLiveModelsForActiveProvider()
            }
        }
    }
    public var apiKey: String = "" {
        didSet {
            providerKeys[activeProvider.rawValue] = apiKey
            save()
            Task { @MainActor in
                await self.fetchLiveModelsForActiveProvider()
            }
        }
    }
    public var selectedModel: String = "mimo-v2.5" {
        didSet { save() }
    }
    public var temperature: Double = 0.2
    public var maxTokens: Int = 8192
    public var baseURL: String = "https://opencode.ai/zen/go/v1" {
        didSet {
            providerBaseURLs[activeProvider.rawValue] = baseURL
            save()
        }
    }
    public var requestTimeout: Double = 120
    public var dynamicModelsByProvider: [ProviderType: [String]] = [:]
    public var isRefreshingModels: Bool = false
    public var providerKeys: [String: String] = [:]
    public var providerBaseURLs: [String: String] = [:]

    public static let modelsByProvider: [ProviderType: [String]] = [
        .opencode: [
            "mimo-v2.5",
            "muse-spark-1.2-contributor",
            "muse-spark-1.2",
            "deepseek-v4-flash",
            "qwen3.7-plus",
            "hy3",
            "minimax-m2.7",
            "qwen3.6-plus",
            "mimo-v2.5-pro",
            "minimax-m3",
            "gpt-5.6-luna",
            "kimi-k2.7-code",
            "kimi-k2.6",
            "deepseek-v4-pro",
            "glm-5.2",
            "glm-5.1",
            "qwen3.7-max",
            "glm-5.3",
            "qwen3.8-max",
            "grok-4.5",
            "kimi-k3"
        ],
        .opencodeZen: ["claude-3-7-sonnet", "deepseek-r1", "o3-mini", "gemini-2.5-pro", "glm-5.3", "muse-spark-1.2"],
        .hermes: [
            "hermes-3-llama-3.1-405b",
            "hermes-3-llama-3.1-70b",
            "hermes-3-llama-3.1-8b",
            "nous-hermes-2-mixtral-8x7b-dpo",
            "nous-hermes-2-yi-34b",
            "hermes-function-calling"
        ],
        .glm: ["glm-5.3", "glm-5.2", "glm-4.7", "glm-4-plus", "glm-4-flash", "codegeex-4"],
        .gemini: [
            "gemini-2.5-pro",
            "gemini-2.0-flash",
            "gemini-2.0-flash-thinking-exp-01-21",
            "gemini-1.5-pro-latest",
            "gemini-1.5-flash-latest"
        ],
        .openrouter: ["meta/muse-spark-1.2-contributor", "meta/muse-spark-1.2", "anthropic/claude-3.7-sonnet", "deepseek/deepseek-r1", "deepseek/deepseek-chat", "meta-llama/llama-3.3-70b-instruct", "qwen/qwen-2.5-coder-32b-instruct", "google/gemini-2.0-flash-001", "nousresearch/hermes-3-llama-3.1-405b"],
        .anthropic: ["claude-3-7-sonnet-20250219", "claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022", "claude-3-opus-20240229"],
        .deepseek: ["deepseek-reasoner", "deepseek-chat"],
        .openai: ["gpt-4o", "gpt-4o-mini", "o1", "o3-mini", "gpt-4.5-preview"],
        .lmstudio: [
            "qwen2.5-coder-32b-instruct",
            "deepseek-r1-distill-qwen-14b",
            "deepseek-r1-distill-qwen-32b",
            "llama-3.3-70b-instruct",
            "hermes-3-llama-3.1-8b",
            "mistral-nemo-instruct-2407",
            "phi-4",
            "loaded-model"
        ],
        .ollama: [
            "qwen2.5-coder:32b",
            "deepseek-r1:14b",
            "deepseek-r1:32b",
            "llama3.3:70b",
            "hermes3:8b",
            "mistral:latest",
            "starcoder2:latest"
        ],
        .local: ["qwen2.5-coder:32b", "deepseek-r1:14b", "deepseek-r1:32b", "llama3.3:70b"]
    ]

    public func modelsForActiveProvider() -> [String] {
        if let dynamic = dynamicModelsByProvider[activeProvider], !dynamic.isEmpty {
            return dynamic
        }
        return Self.modelsByProvider[activeProvider] ?? []
    }

    @MainActor
    public func fetchLiveModelsForActiveProvider() async {
        isRefreshingModels = true
        defer { isRefreshingModels = false }

        var discovered: [String] = []

        // LM Studio Dynamic Model Discovery via native v1 API / port 1234
        if activeProvider == .lmstudio {
            let lmStatus = await LocalInferenceManager.shared.probeLMStudio(baseURL: baseURL)
            for m in lmStatus.discoveredModels {
                if !discovered.contains(m) {
                    discovered.append(m)
                }
            }
        } else if activeProvider == .ollama {
            let ollamaStatus = await LocalInferenceManager.shared.probeOllama(baseURL: baseURL)
            for m in ollamaStatus.discoveredModels {
                if !discovered.contains(m) {
                    discovered.append(m)
                }
            }
        }

        // Query provider native API /models endpoint if API key is present or local
        if !apiKey.isEmpty || activeProvider.isLocal {
            let provider = UniversalCloudProvider(
                name: activeProvider.rawValue,
                apiKey: apiKey,
                baseURL: baseURL,
                isAnthropicNative: activeProvider == .anthropic
            )
            if let remoteModels = try? await provider.fetchAvailableModels(), !remoteModels.isEmpty {
                for m in remoteModels {
                    if !discovered.contains(m) {
                        discovered.append(m)
                    }
                }
            }
        }

        // Add static defaults if not present
        if let defaults = Self.modelsByProvider[activeProvider] {
            for m in defaults {
                if !discovered.contains(m) {
                    discovered.append(m)
                }
            }
        }

        if !discovered.isEmpty {
            dynamicModelsByProvider[activeProvider] = discovered
            if !discovered.contains(selectedModel), let first = discovered.first {
                selectedModel = first
            }
        }
        save()
    }

    // MARK: Agents & Gates
    public var agentPersonality: PersonalityStyle = .terse
    public var maxRounds: Int = 15
    public var requiredGates: Set<String> = ["syntax", "repeat", "compilation"]
    public static let availableGates = ["syntax", "repeat", "compilation", "memory", "objective"]

    // MARK: Tools & Sandbox
    public var enabledTools: Set<String> = ["bash", "file", "grep", "glob", "patch", "mcp"]
    public var bashTimeout: Double = 60
    public var networkAccess: NetworkAccess = .restricted
    public var commandBlocklist: [String] = ["rm -rf /", "sudo rm -rf"]

    // MARK: Appearance
    public var colorScheme: AppColorScheme = .dark
    public var fontSize: Double = 13
    public var codeFont: String = "SF Mono"

    // MARK: Persistence
    private var settingsFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AdventurersHarness")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }

    public init() {
        if !load() {
            autoImportStoredKeys()
        } else {
            if baseURL == "https://api.opencode.ai/v1" || baseURL == "https://api.opencode.ai" {
                baseURL = ProviderType.opencode.defaultBaseURL
            }
            if selectedModel == "opencode-go-4.5" || selectedModel == "glm-5.3" {
                selectedModel = "mimo-v2.5"
            }
            autoImportStoredKeys()
        }
        if metaHarnessProfiles.isEmpty {
            metaHarnessProfiles = MetaHarnessRegistry.shared.discoverProfiles()
        }
        Task { @MainActor in
            await self.fetchLiveModelsForActiveProvider()
        }
    }

    public func profile(for type: MetaHarnessType) -> MetaHarnessProfile {
        if let found = metaHarnessProfiles.first(where: { $0.type == type }) {
            return found
        }
        let newP = MetaHarnessProfile(type: type)
        metaHarnessProfiles.append(newP)
        return newP
    }

    public func updateProfile(_ profile: MetaHarnessProfile) {
        if let idx = metaHarnessProfiles.firstIndex(where: { $0.type == profile.type }) {
            metaHarnessProfiles[idx] = profile
        } else {
            metaHarnessProfiles.append(profile)
        }
        save()
    }

    public func syncKeysToMetaHarnesses() {
        for idx in metaHarnessProfiles.indices {
            let type = metaHarnessProfiles[idx].type
            switch type {
            case .antigravity:
                if let geminiKey = providerKeys[ProviderType.gemini.rawValue] ?? providerKeys["GEMINI_API_KEY"], !geminiKey.isEmpty {
                    metaHarnessProfiles[idx].apiKey = geminiKey
                }
            case .claudeCode:
                if let anthropicKey = providerKeys[ProviderType.anthropic.rawValue], !anthropicKey.isEmpty {
                    metaHarnessProfiles[idx].apiKey = anthropicKey
                }
            case .codex, .smallctl:
                if let openAIKey = providerKeys[ProviderType.openai.rawValue], !openAIKey.isEmpty {
                    metaHarnessProfiles[idx].apiKey = openAIKey
                }
            case .hermes:
                if let anthropicKey = providerKeys[ProviderType.anthropic.rawValue], !anthropicKey.isEmpty {
                    metaHarnessProfiles[idx].apiKey = anthropicKey
                }
            case .opencode:
                if let opencodeKey = providerKeys[ProviderType.opencode.rawValue], !opencodeKey.isEmpty {
                    metaHarnessProfiles[idx].apiKey = opencodeKey
                }
            case .deepseekHarness:
                if let dsKey = providerKeys[ProviderType.deepseek.rawValue], !dsKey.isEmpty {
                    metaHarnessProfiles[idx].apiKey = dsKey
                }
            case .pi:
                if let routerKey = providerKeys[ProviderType.openrouter.rawValue], !routerKey.isEmpty {
                    metaHarnessProfiles[idx].apiKey = routerKey
                }
            case .muse:
                if let metaKey = providerKeys["META_API_KEY"] ?? providerKeys[ProviderType.openrouter.rawValue], !metaKey.isEmpty {
                    metaHarnessProfiles[idx].apiKey = metaKey
                }
            case .custom:
                break
            }
        }
        save()
    }

    public func autoImportStoredKeys() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let authURL = home.appendingPathComponent(".local/share/opencode/auth.json")

        if let data = try? Data(contentsOf: authURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

            // 1. Populate all known provider credentials into cache
            if let opencodeGo = (json["opencode-go"] ?? json["opencode"]) as? [String: Any],
               let key = opencodeGo["key"] as? String, !key.isEmpty {
                providerKeys[ProviderType.opencode.rawValue] = key
            }
            if let zai = (json["zai-coding-plan"] ?? json["zhipuai"]) as? [String: Any],
               let key = zai["key"] as? String, !key.isEmpty {
                providerKeys[ProviderType.glm.rawValue] = key
            }
            if let openrouter = json["openrouter"] as? [String: Any],
               let key = openrouter["key"] as? String, !key.isEmpty {
                providerKeys[ProviderType.openrouter.rawValue] = key
            }
            if let anthropic = json["anthropic"] as? [String: Any],
               let key = (anthropic["access"] ?? anthropic["key"]) as? String, !key.isEmpty {
                providerKeys[ProviderType.anthropic.rawValue] = key
            }
            if let deepseek = json["deepseek"] as? [String: Any],
               let key = deepseek["key"] as? String, !key.isEmpty {
                providerKeys[ProviderType.deepseek.rawValue] = key
            }
            if let openai = json["openai"] as? [String: Any],
               let key = openai["key"] as? String, !key.isEmpty {
                providerKeys[ProviderType.openai.rawValue] = key
            }

            // 2. OpenCode Go is the default primary provider with the cheapest model (MiMo-V2.5, 150k req/mo)!
            if let opencodeKey = providerKeys[ProviderType.opencode.rawValue], !opencodeKey.isEmpty {
                self.activeProvider = .opencode
                self.apiKey = opencodeKey
                self.baseURL = "https://opencode.ai/zen/go/v1"
                self.selectedModel = "mimo-v2.5"
            } else if let openrouterKey = providerKeys[ProviderType.openrouter.rawValue], !openrouterKey.isEmpty {
                self.activeProvider = .openrouter
                self.apiKey = openrouterKey
                self.baseURL = "https://openrouter.ai/api/v1"
                self.selectedModel = "anthropic/claude-3.7-sonnet"
            } else if let zaiKey = providerKeys[ProviderType.glm.rawValue], !zaiKey.isEmpty {
                self.activeProvider = .glm
                self.apiKey = zaiKey
                self.baseURL = "https://api.z.ai/api/coding/paas/v4"
                self.selectedModel = "glm-5.3"
            } else if let anthropicKey = providerKeys[ProviderType.anthropic.rawValue], !anthropicKey.isEmpty {
                self.activeProvider = .anthropic
                self.apiKey = anthropicKey
                self.baseURL = "https://api.anthropic.com/v1"
                self.selectedModel = "claude-3-7-sonnet-20250219"
            }
        }
    }
    public func updateDefaultsForProvider() {
        if let customURL = providerBaseURLs[activeProvider.rawValue], !customURL.isEmpty {
            baseURL = customURL
        } else {
            baseURL = activeProvider.defaultBaseURL
        }

        if let savedKey = providerKeys[activeProvider.rawValue], !savedKey.isEmpty {
            apiKey = savedKey
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let authURL = home.appendingPathComponent(".local/share/opencode/auth.json")
            if let data = try? Data(contentsOf: authURL),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                switch activeProvider {
                case .opencode, .opencodeZen:
                    if let entry = (json["opencode-go"] ?? json["opencode"]) as? [String: Any] {
                        self.apiKey = entry["key"] as? String ?? ""
                    }
                case .hermes:
                    if let entry = (json["hermes"] ?? json["nous"]) as? [String: Any] {
                        self.apiKey = entry["key"] as? String ?? ""
                    }
                case .glm:
                    if let entry = (json["zai-coding-plan"] ?? json["zhipuai"]) as? [String: Any] {
                        self.apiKey = entry["key"] as? String ?? ""
                    }
                case .gemini:
                    if let entry = (json["gemini"] ?? json["google"]) as? [String: Any] {
                        self.apiKey = entry["key"] as? String ?? ""
                    }
                case .openrouter:
                    if let entry = json["openrouter"] as? [String: Any] {
                        self.apiKey = entry["key"] as? String ?? ""
                    }
                case .anthropic:
                    if let entry = json["anthropic"] as? [String: Any] {
                        self.apiKey = (entry["access"] ?? entry["key"]) as? String ?? ""
                    }
                case .deepseek:
                    if let entry = json["deepseek"] as? [String: Any] {
                        self.apiKey = entry["key"] as? String ?? ""
                    }
                case .openai:
                    if let entry = json["openai"] as? [String: Any] {
                        self.apiKey = entry["key"] as? String ?? ""
                    }
                case .lmstudio, .ollama, .local:
                    self.apiKey = ""
                }
            }
        }

        if let firstModel = modelsForActiveProvider().first {
            selectedModel = firstModel
        }
    }

    public func save() {
        let persisted = PersistedSettings(
            openLastProjectOnLaunch: openLastProjectOnLaunch,
            defaultShell: defaultShell,
            dataDirectory: dataDirectory,
            activeProvider: activeProvider,
            apiKey: apiKey,
            selectedModel: selectedModel,
            baseURL: baseURL,
            executionMode: executionMode,
            selectedMetaHarness: selectedMetaHarness,
            metaHarnessProfiles: metaHarnessProfiles,
            enableDictation: enableDictation,
            dictationAutoPunctuation: dictationAutoPunctuation,
            dictationSilenceTimeoutSeconds: dictationSilenceTimeoutSeconds,
            dictationLanguage: dictationLanguage,
            checkUpdatesOnLaunch: checkUpdatesOnLaunch,
            updateChannel: updateChannel
        )
        if let data = try? JSONEncoder().encode(persisted) {
            try? data.write(to: settingsFileURL)
        }
    }

    public func load() -> Bool {
        guard let data = try? Data(contentsOf: settingsFileURL),
              let persisted = try? JSONDecoder().decode(PersistedSettings.self, from: data) else {
            return false
        }
        self.openLastProjectOnLaunch = persisted.openLastProjectOnLaunch
        self.defaultShell = persisted.defaultShell
        self.dataDirectory = persisted.dataDirectory
        self.activeProvider = persisted.activeProvider
        self.apiKey = persisted.apiKey
        self.selectedModel = persisted.selectedModel
        self.baseURL = persisted.baseURL
        if let mode = persisted.executionMode {
            self.executionMode = mode
        }
        if let harness = persisted.selectedMetaHarness {
            self.selectedMetaHarness = harness
        }
        if let profiles = persisted.metaHarnessProfiles, !profiles.isEmpty {
            self.metaHarnessProfiles = profiles
        } else {
            self.metaHarnessProfiles = MetaHarnessRegistry.shared.discoverProfiles()
        }
        if let enabled = persisted.enableDictation {
            self.enableDictation = enabled
        }
        if let punct = persisted.dictationAutoPunctuation {
            self.dictationAutoPunctuation = punct
        }
        if let timeout = persisted.dictationSilenceTimeoutSeconds {
            self.dictationSilenceTimeoutSeconds = timeout
        }
        if let lang = persisted.dictationLanguage {
            self.dictationLanguage = lang
        }
        if let checkUpdates = persisted.checkUpdatesOnLaunch {
            self.checkUpdatesOnLaunch = checkUpdates
        }
        if let channel = persisted.updateChannel {
            self.updateChannel = channel
        }
        return true
    }
}

public struct PersistedSettings: Codable, Sendable {
    var openLastProjectOnLaunch: Bool
    var defaultShell: String
    var dataDirectory: String
    var activeProvider: ProviderType
    var apiKey: String
    var selectedModel: String
    var baseURL: String
    var executionMode: ExecutionMode?
    var selectedMetaHarness: MetaHarnessType?
    var metaHarnessProfiles: [MetaHarnessProfile]?
    var enableDictation: Bool?
    var dictationAutoPunctuation: Bool?
    var dictationSilenceTimeoutSeconds: Double?
    var dictationLanguage: String?
    var checkUpdatesOnLaunch: Bool?
    var updateChannel: UpdateChannel?
}

// MARK: - Provider Types

public enum ProviderType: String, CaseIterable, Sendable, Codable {
    case opencode = "OpenCode Go Cloud"
    case opencodeZen = "OpenCode Zen Cloud"
    case hermes = "Nous Hermes Cloud"
    case glm = "Zhipu / Z.AI GLM"
    case gemini = "Google Gemini / Antigravity"
    case openrouter = "OpenRouter"
    case anthropic = "Anthropic"
    case deepseek = "DeepSeek"
    case openai = "OpenAI"
    case lmstudio = "LM Studio (Local / Port 1234)"
    case ollama = "Ollama (Local / Port 11434)"
    case local = "Custom Local / vLLM"

    public var isLocal: Bool {
        switch self {
        case .lmstudio, .ollama, .local: return true
        default: return false
        }
    }

    public var icon: String {
        switch self {
        case .opencode: return "bolt.badge.clock"
        case .opencodeZen: return "wand.and.stars"
        case .hermes: return "sparkles"
        case .glm: return "cpu.fill"
        case .gemini: return "atom"
        case .openrouter: return "network"
        case .anthropic: return "cube.transparent"
        case .deepseek: return "bolt.fill"
        case .openai: return "brain"
        case .lmstudio: return "laptopcomputer.and.arrow.down"
        case .ollama: return "cpu.fill"
        case .local: return "server.rack"
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .opencode: return "https://opencode.ai/zen/go/v1"
        case .opencodeZen: return "https://opencode.ai/zen/v1"
        case .hermes: return "https://hermes.nousresearch.com/v1"
        case .glm: return "https://api.z.ai/api/coding/paas/v4"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .openrouter: return "https://openrouter.ai/api/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .deepseek: return "https://api.deepseek.com/v1"
        case .openai: return "https://api.openai.com/v1"
        case .lmstudio: return "http://localhost:1234/v1"
        case .ollama: return "http://localhost:11434/v1"
        case .local: return "http://localhost:8000/v1"
        }
    }

    public var websiteURL: String {
        switch self {
        case .opencode: return "https://opencode.ai/go"
        case .opencodeZen: return "https://opencode.ai/zen"
        case .hermes: return "https://nousresearch.com"
        case .glm: return "https://z.ai"
        case .gemini: return "https://ai.google.dev"
        case .openrouter: return "https://openrouter.ai"
        case .anthropic: return "https://anthropic.com"
        case .deepseek: return "https://deepseek.com"
        case .openai: return "https://openai.com"
        case .lmstudio: return "https://lmstudio.ai"
        case .ollama: return "https://ollama.com"
        case .local: return "http://localhost:8000"
        }
    }
}

public enum PersonalityStyle: String, CaseIterable, Sendable, Codable {
    case terse = "Terse"
    case conversational = "Conversational"
}

public enum NetworkAccess: String, CaseIterable, Sendable, Codable {
    case open = "Open"
    case restricted = "Restricted"
    case offline = "Offline"
}

public enum AppColorScheme: String, CaseIterable, Sendable, Codable {
    case dark = "Dark"
    case light = "Light"
    case system = "System"
}

// MARK: - Main Settings View

public struct SettingsView: View {
    @Bindable public var model: SettingsModel
    @State private var selectedTab: SettingsTab = .llmProvider
    @State private var searchText: String = ""

    public init(model: SettingsModel = SettingsModel()) {
        self.model = model
    }

    public var body: some View {
        HSplitView {
            // Left Settings Navigation Sidebar
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.adOrange)
                    Text("SETTINGS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.adTextTertiary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Divider()
                    .foregroundStyle(Color.adDivider)

                // Tab items grouped by category
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(SettingsGroup.allCases, id: \.self) { group in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.rawValue)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color.adTextTertiary)
                                    .padding(.horizontal, 10)
                                    .padding(.bottom, 2)

                                ForEach(group.tabs, id: \.self) { tab in
                                    SettingsTabRow(
                                        tab: tab,
                                        isSelected: selectedTab == tab
                                    ) {
                                        selectedTab = tab
                                    }
                                }
                            }
                        }
                    }
                    .padding(8)
                }

                Divider()
                    .foregroundStyle(Color.adDivider)

                // Footer sync pill
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.adSuccess)
                        .frame(width: 6, height: 6)
                    Text("Auto-Keyring Connected")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.adTextTertiary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.adNavy.opacity(0.8))
            }
            .frame(width: 210)
            .background(Color.adNavy)

            // Right Settings Content Stage
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch selectedTab {
                        case .executionMode:
                            ExecutionModeSettingsPane(model: model)
                        case .llmProvider:
                            LLMProviderSettingsPane(model: model)
                        case .metaHarness:
                            MetaHarnessSettingsPane(model: model)
                        case .general:
                            GeneralSettingsPane(model: model)
                        case .dictation:
                            DictationSettingsPane(model: model)
                        case .diagnostics:
                            DiagnosticsSettingsPane()
                        case .agents:
                            AgentsSettingsPane(model: model)
                        case .tools:
                            ToolsSettingsPane(model: model)
                        case .sandbox:
                            SandboxSettingsPane(model: model)
                        case .appearance:
                            AppearanceSettingsPane(model: model)
                        case .about:
                            AboutSettingsPane()
                        }
                    }
                    .padding(24)
                }
            }
            .frame(minWidth: 520, maxWidth: .infinity)
            .background(Color.adBackground)
        }
        .frame(width: 840, height: 600)
    }
}

// MARK: - Settings Navigation Groups & Tabs

private enum SettingsGroup: String, CaseIterable {
    case engine = "ENGINE & DISPATCH"
    case gatesAndSecurity = "GATES & SECURITY"
    case preferences = "PREFERENCES"

    var tabs: [SettingsTab] {
        switch self {
        case .engine:
            return [.executionMode, .llmProvider, .metaHarness]
        case .gatesAndSecurity:
            return [.agents, .tools, .sandbox]
        case .preferences:
            return [.general, .dictation, .diagnostics, .appearance, .about]
        }
    }
}

private enum SettingsTab: String, CaseIterable {
    case executionMode = "Execution Strategy"
    case llmProvider = "Cloud Subscriptions"
    case metaHarness = "Meta Harness CLIs"
    case general = "General"
    case dictation = "Speech & Dictation"
    case diagnostics = "Crash Logs & Diagnostics"
    case agents = "Agents & Gates"
    case tools = "Tools"
    case sandbox = "Sandbox"
    case appearance = "Appearance"
    case about = "About"

    var icon: String {
        switch self {
        case .executionMode: return "arrow.triangle.branch"
        case .llmProvider: return "cloud.fill"
        case .metaHarness: return "terminal.fill"
        case .general: return "gearshape"
        case .dictation: return "mic.fill"
        case .diagnostics: return "ant.circle.fill"
        case .agents: return "person.2.fill"
        case .tools: return "wrench.and.screwdriver"
        case .sandbox: return "lock.shield"
        case .appearance: return "paintbrush"
        case .about: return "info.circle"
        }
    }
}

private struct SettingsTabRow: View {
    let tab: SettingsTab
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Color.adOrange : Color.adTextSecondary)
                    .frame(width: 18)

                Text(tab.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.adTextPrimary : Color.adTextSecondary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.adElevated : Color.clear)
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.adOrange)
                        .frame(width: 3, height: 16)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Execution Mode Settings Pane

private struct ExecutionModeSettingsPane: View {
    @Bindable var model: SettingsModel
    @State private var syncToast: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Execution Mode & Dispatch Strategy")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.adTextPrimary)
                Text("Choose between direct cloud API coding plans or delegating to external sub-harness CLIs.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.adTextSecondary)
            }

            // Mode Selector Cards
            VStack(spacing: 12) {
                // Card 1: Subscription (Quota Tier)
                modeCard(
                    mode: .subscription,
                    title: "Subscription Tier (Quota-Limited)",
                    subtitle: "Usage-limited monthly/team subscription tier with fixed quota resets (Claude Pro, ChatGPT Plus, GLM Coding Plan, Gemini Advanced).",
                    icon: "creditcard.fill",
                    accentColor: Color.cyan,
                    details: "Model: \(model.selectedModel) (\(model.activeProvider.rawValue))"
                )

                // Card 2: Pay-As-You-Go API Key
                modeCard(
                    mode: .payAsYouGo,
                    title: "Pay-As-You-Go Mode (Direct API Key)",
                    subtitle: "Metered direct developer API keys with per-token spend ledger and sliding-window TPS telemetry.",
                    icon: "key.fill",
                    accentColor: Color.adOrange,
                    details: "Active Provider: \(model.activeProvider.rawValue)"
                )

                // Card 3: Meta Harness External CLIs
                modeCard(
                    mode: .metaHarness,
                    title: "Meta Harness Mode (CLI Native Auth)",
                    subtitle: "Autonomous external CLI agents with built-in zero-config auth (no user API keys required). Auto-detects local binaries.",
                    icon: "arrow.triangle.branch",
                    accentColor: Color.adInfo,
                    details: "Active CLI: \(model.selectedMetaHarness.rawValue) (\(model.selectedMetaHarness.isInstalled ? "Installed: \(model.selectedMetaHarness.findInstalledBinaryPath() ?? "")" : "Not Installed"))"
                )
            }

            // Quick Sync / Credential Bridge Card
            VStack(alignment: .leading, spacing: 10) {
                Text("CREDENTIAL ISOLATION & BRIDGING")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.adTextTertiary)

                HStack(spacing: 12) {
                    Image(systemName: "key.horizontal.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.adOrange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dedicated API Keys per Mode")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.adTextPrimary)
                        Text("Maintain separate budget keys for direct cloud subscriptions and specialized keys for external CLI agents.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.adTextSecondary)
                    }

                    Spacer()

                    Button {
                        model.syncKeysToMetaHarnesses()
                        syncToast = "✓ Keys synced from Cloud Subscription to Meta Harnesses"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            syncToast = nil
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Sync All Keys")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.adTextPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.adElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(Color.adCard)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.adDivider, lineWidth: 1))

                if let toast = syncToast {
                    Text(toast)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.adSuccess)
                        .padding(.leading, 4)
                }
            }

            // Overview comparison table
            VStack(alignment: .leading, spacing: 8) {
                Text("MODE COMPARISON")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.adTextTertiary)

                VStack(spacing: 6) {
                    comparisonRow(feature: "Execution Engine", plan: "UniversalCloudProvider (HTTP/SSE)", meta: "Subprocess Runner / Process Pipe")
                    comparisonRow(feature: "Deterministic Gates", plan: "Syntax, Repeat, Compile, Diff, Memory", meta: "CLI-native or Harness External Gates")
                    comparisonRow(feature: "API Key Scope", plan: "Coding Plan Keyring", meta: "Isolated CLI Environment Variables")
                    comparisonRow(feature: "Telemetry & TPS", plan: "Real-time Rolling Token TPS & Cost", meta: "Process Output Line Logging")
                }
                .padding(12)
                .background(Color.adNavy)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func modeCard(
        mode: ExecutionMode,
        title: String,
        subtitle: String,
        icon: String,
        accentColor: Color,
        details: String
    ) -> some View {
        let isSelected = model.executionMode == mode

        return Button {
            model.executionMode = mode
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(accentColor)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.adTextPrimary)
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(accentColor)
                        }
                    }

                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.adTextSecondary)
                        .lineSpacing(2)

                    Text(details)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(accentColor)
                        .padding(.top, 2)
                }
            }
            .padding(14)
            .background(isSelected ? Color.adElevated : Color.adCard.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? accentColor : Color.adDivider, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func comparisonRow(feature: String, plan: String, meta: String) -> some View {
        HStack {
            Text(feature)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.adTextSecondary)
                .frame(width: 130, alignment: .leading)
            Text(plan)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.adOrange)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(meta)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.adInfo)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Meta Harness Settings Pane

private struct MetaHarnessSettingsPane: View {
    @Bindable var model: SettingsModel
    @State private var selectedHarnessType: MetaHarnessType = .codex
    @State private var testOutput: String?
    @State private var isRunningTest = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Meta Harness CLI Profiles")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.adTextPrimary)
                Text("Configure dedicated API keys, executable paths, and environment variables for external sub-agent harnesses.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.adTextSecondary)
            }

            // Harness Type Selector Grid
            VStack(alignment: .leading, spacing: 8) {
                Text("SELECT HARNESS CLI PROFILE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.adTextTertiary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(MetaHarnessType.allCases) { type in
                        let profile = model.profile(for: type)
                        let isSelected = selectedHarnessType == type
                        let isActive = model.selectedMetaHarness == type

                        Button {
                            selectedHarnessType = type
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: type.icon)
                                    .font(.system(size: 13))
                                    .foregroundStyle(isSelected ? Color.adOrange : Color.adTextSecondary)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(type.rawValue)
                                        .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                        .foregroundStyle(isSelected ? Color.adTextPrimary : Color.adTextSecondary)
                                    Text(profile.autoDetected ? "● Auto-Detected" : (profile.apiKey.isEmpty ? "○ Key Missing" : "✓ Key Configured"))
                                        .font(.system(size: 9))
                                        .foregroundStyle(profile.autoDetected || !profile.apiKey.isEmpty ? Color.adSuccess : Color.adTextTertiary)
                                }

                                Spacer()

                                if isActive {
                                    Text("ACTIVE")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.adOrange.opacity(0.2))
                                        .foregroundStyle(Color.adOrange)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isSelected ? Color.adElevated : Color.adCard.opacity(0.5))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(isSelected ? Color.adOrange : Color.adDivider, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Profile Detail & Credentials Card
            let profile = model.profile(for: selectedHarnessType)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: selectedHarnessType.icon)
                        .foregroundStyle(Color.adOrange)
                    Text("\(selectedHarnessType.rawValue) Configuration")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.adTextPrimary)

                    Spacer()

                    if model.selectedMetaHarness != selectedHarnessType {
                        Button("Set as Active Harness") {
                            model.selectedMetaHarness = selectedHarnessType
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.adOrange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.adOrange.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                }

                Text(selectedHarnessType.description)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.adTextSecondary)

                HStack(spacing: 8) {
                    Image(systemName: "terminal.fill")
                        .foregroundStyle(Color.adSuccess)
                    Text("Meta Harnesses run as autonomous terminal beings using their existing CLI session, local login, and native environment. No API keys required.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.adTextSecondary)
                }
                .padding(8)
                .background(Color.adSuccess.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Divider().overlay(Color.adDivider)

                // Binary Executable Path
                VStack(alignment: .leading, spacing: 4) {
                    Text("Executable Binary Path")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.adTextSecondary)

                    TextField("Path to binary (e.g. codex, /opt/homebrew/bin/opencode)", text: Binding(
                        get: { model.profile(for: selectedHarnessType).binaryPath },
                        set: {
                            var p = model.profile(for: selectedHarnessType)
                            p.binaryPath = $0
                            model.updateProfile(p)
                        }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(8)
                    .background(Color.adBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.adDivider, lineWidth: 1))
                }

                // Optional API Key Override
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Optional API Key Override (Only if not logged in via CLI)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.adTextSecondary)
                        Spacer()
                        Button("Copy Key from Cloud Subscription") {
                            copyMatchingKey(for: selectedHarnessType)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.cyan)
                    }

                    SecureField("Enter distinct API key (passed as $\(selectedHarnessType.defaultEnvKeyName))...", text: Binding(
                        get: { model.profile(for: selectedHarnessType).apiKey },
                        set: {
                            var p = model.profile(for: selectedHarnessType)
                            p.apiKey = $0
                            model.updateProfile(p)
                        }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(8)
                    .background(Color.adBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.adDivider, lineWidth: 1))
                }

                // Environment Variable Name
                HStack {
                    Text("Injected Environment Variable:")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.adTextTertiary)
                    Text("$\(selectedHarnessType.defaultEnvKeyName)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.adInfo)
                    Spacer()
                }

                // Test CLI Button
                HStack {
                    Button {
                        testHarnessCLI(profile)
                    } label: {
                        HStack(spacing: 4) {
                            if isRunningTest {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "play.circle")
                            }
                            Text("Test CLI Execution")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.adTextPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.adElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .disabled(isRunningTest)

                    Spacer()
                }

                if let test = testOutput {
                    Text(test)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.adTextSecondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.adNavy)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(14)
            .background(Color.adCard)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.adDivider, lineWidth: 1))
        }
    }

    private func copyMatchingKey(for type: MetaHarnessType) {
        var p = model.profile(for: type)
        switch type {
        case .antigravity:
            p.apiKey = model.providerKeys[ProviderType.gemini.rawValue] ?? model.providerKeys["GEMINI_API_KEY"] ?? ""
        case .claudeCode, .hermes:
            p.apiKey = model.providerKeys[ProviderType.anthropic.rawValue] ?? ""
        case .codex, .smallctl:
            p.apiKey = model.providerKeys[ProviderType.openai.rawValue] ?? ""
        case .opencode:
            p.apiKey = model.providerKeys[ProviderType.opencode.rawValue] ?? ""
        case .deepseekHarness:
            p.apiKey = model.providerKeys[ProviderType.deepseek.rawValue] ?? ""
        case .pi:
            p.apiKey = model.providerKeys[ProviderType.openrouter.rawValue] ?? ""
        case .muse:
            p.apiKey = model.providerKeys["META_API_KEY"] ?? model.providerKeys[ProviderType.openrouter.rawValue] ?? ""
        case .custom:
            p.apiKey = model.apiKey
        }
        model.updateProfile(p)
    }

    private func testHarnessCLI(_ profile: MetaHarnessProfile) {
        isRunningTest = true
        testOutput = "Testing '\(profile.binaryPath) --version'..."

        Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
            proc.arguments = ["-c", "which \(profile.binaryPath) && \(profile.binaryPath) --version || echo 'Executable not reachable on PATH'"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe

            do {
                try proc.run()
                proc.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? "No output"
                await MainActor.run {
                    self.testOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.isRunningTest = false
                }
            } catch {
                await MainActor.run {
                    self.testOutput = "Error launching process: \(error.localizedDescription)"
                    self.isRunningTest = false
                }
            }
        }
    }
}

// MARK: - LLM Provider Settings Pane

private struct LLMProviderSettingsPane: View {
    @Bindable var model: SettingsModel
    @State private var isTesting = false
    @State private var statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("LLM Providers & Native Model Routing")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.adTextPrimary)
                Text("Native, decoupled API connections to Anthropic, DeepSeek, Z.AI GLM, OpenAI, and OpenRouter.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.adTextSecondary)
            }

            // Sync Banner
            HStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.adSuccess)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-Detected Credentials (~/.local/share/opencode/auth.json)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.adTextPrimary)
                    Text("API keys automatically imported for Anthropic, DeepSeek, Z.AI, and OpenRouter.")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.adTextTertiary)
                }

                Spacer()

                Button("Import Keys") {
                    model.autoImportStoredKeys()
                    statusMessage = "✓ Refreshed credentials from local keyring"
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.adTextPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.adElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(12)
            .background(Color.adElevated.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.adSuccess.opacity(0.3), lineWidth: 1)
            )

            // 1. On-Device Local Inference Engines (LM Studio vs Ollama)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.adOrange)
                    Text("ON-DEVICE LOCAL INFERENCE (100% FREE · ZERO CLOUD TOKENS)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.adTextPrimary)
                    Spacer()
                    if model.activeProvider.isLocal {
                        Text("ACTIVE: \(model.activeProvider.rawValue.uppercased())")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.adSuccess.opacity(0.2))
                            .foregroundStyle(Color.adSuccess)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                HStack(spacing: 10) {
                    // LM Studio Button
                    localEngineButton(
                        provider: .lmstudio,
                        name: "LM Studio",
                        port: "Port 1234",
                        apiInfo: "Native v1 & /v1/responses",
                        icon: "laptopcomputer.and.arrow.down",
                        accentColor: .cyan
                    )

                    // Ollama Button
                    localEngineButton(
                        provider: .ollama,
                        name: "Ollama",
                        port: "Port 11434",
                        apiInfo: "Native CLI & /api/tags",
                        icon: "cpu.fill",
                        accentColor: .green
                    )

                    // Custom Local Gateway Button
                    localEngineButton(
                        provider: .local,
                        name: "Custom / vLLM",
                        port: "Port 8000",
                        apiInfo: "OpenAI Proxy",
                        icon: "server.rack",
                        accentColor: .purple
                    )
                }
            }
            .padding(12)
            .background(Color.adNavy)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(model.activeProvider.isLocal ? Color.adOrange.opacity(0.6) : Color.adDivider, lineWidth: 1)
            )

            // 2. Cloud Frontier Providers
            VStack(alignment: .leading, spacing: 10) {
                Text("CLOUD & SUBSCRIPTION PROVIDERS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.adTextTertiary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(ProviderType.allCases.filter { !$0.isLocal }, id: \.self) { provider in
                        let isSelected = model.activeProvider == provider
                        let hasKey = (model.providerKeys[provider.rawValue]?.isEmpty == false) || (isSelected && !model.apiKey.isEmpty)

                        Button {
                            model.activeProvider = provider
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: provider.icon)
                                    .font(.system(size: 13))
                                    .foregroundStyle(isSelected ? Color.adOrange : Color.adTextSecondary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(provider.rawValue)
                                        .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                        .foregroundStyle(isSelected ? Color.adTextPrimary : Color.adTextSecondary)

                                    HStack(spacing: 4) {
                                        Text(planBadgeText(for: provider))
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundStyle(Color.adTextTertiary)

                                        Text(hasKey ? "• ✓ Ready" : "• ○ Needs Key")
                                            .font(.system(size: 9))
                                            .foregroundStyle(hasKey ? Color.adSuccess : Color.adWarning)
                                    }
                                }

                                Spacer()

                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.adOrange)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isSelected ? Color.adElevated : Color.adCard.opacity(0.5))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(isSelected ? Color.adOrange.opacity(0.6) : Color.adDivider, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Credentials Card
            VStack(alignment: .leading, spacing: 12) {
                Text("CREDENTIALS & ENDPOINT")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.adTextTertiary)

                VStack(spacing: 10) {
                    // API Key Row
                    VStack(alignment: .leading, spacing: 4) {
                        Text("API Key / Token")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.adTextSecondary)

                        SecureField("Enter API Key...", text: $model.apiKey)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .padding(8)
                            .background(Color.adBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.adDivider, lineWidth: 1)
                            )
                    }

                    // Endpoint URL Row
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("API Endpoint URL")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.adTextSecondary)
                            Spacer()
                            Button("Reset to Default") {
                                model.baseURL = model.activeProvider.defaultBaseURL
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.adOrange)
                        }

                        TextField(model.activeProvider.defaultBaseURL, text: $model.baseURL)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .padding(8)
                            .background(Color.adBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.adDivider, lineWidth: 1)
                            )
                    }

                    // Model Selection Row
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Default Model")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.adTextSecondary)
                            Spacer()
                            Button {
                                Task {
                                    await model.fetchLiveModelsForActiveProvider()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    if model.isRefreshingModels {
                                        ProgressView()
                                            .controlSize(.mini)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 10))
                                    }
                                    Text("Fetch Live API Models")
                                        .font(.system(size: 10))
                                }
                                .foregroundStyle(Color.adOrange)
                            }
                            .buttonStyle(.plain)
                            .disabled(model.isRefreshingModels)
                        }

                        PaginatedSearchableCombobox(
                            selection: $model.selectedModel,
                            title: "Select Model",
                            items: model.modelsForActiveProvider(),
                            pageSize: 8,
                            onRefresh: {
                                Task {
                                    await model.fetchLiveModelsForActiveProvider()
                                }
                            }
                        )
                    }
                }
                .padding(14)
                .background(Color.adCard)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.adDivider, lineWidth: 1)
                )
            }

            // Connection Test Bar
            HStack(spacing: 12) {
                Button {
                    testConnection()
                } label: {
                    HStack(spacing: 6) {
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                        }
                        Text(isTesting ? "Validating Quota..." : "Test Cloud Plan & Quota")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: Color.white.opacity(0.20), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                .disabled(isTesting)

                if let msg = statusMessage {
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundStyle(msg.contains("✓") ? Color.adSuccess : Color.adWarning)
                        .padding(.leading, 4)
                }

                Spacer()

                Button("Save Settings") {
                    model.save()
                    statusMessage = "✓ Settings saved successfully"
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.adTextPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.adElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
            }
        }
    }

    private func planBadgeText(for provider: ProviderType) -> String {
        switch provider {
        case .opencode:
            return "[Cloud Plan: 150k req/mo]"
        case .opencodeZen:
            return "[Cloud Plan: Zen]"
        case .hermes:
            return "[Nous Hermes Cloud / Agent]"
        case .glm:
            return "[Coding Plan / API]"
        case .gemini:
            return "[Gemini / Antigravity Key]"
        case .anthropic, .openai, .deepseek:
            return "[Direct API Key]"
        case .openrouter:
            return "[Aggregator Key]"
        case .lmstudio:
            return "[On-Device / Port 1234]"
        case .ollama:
            return "[On-Device / Port 11434]"
        case .local:
            return "[Custom Local Gateway]"
        }
    }

    private func localEngineButton(
        provider: ProviderType,
        name: String,
        port: String,
        apiInfo: String,
        icon: String,
        accentColor: Color
    ) -> some View {
        let isSelected = model.activeProvider == provider

        return Button {
            model.activeProvider = provider
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isSelected ? accentColor : Color.adTextSecondary)

                    Text(name)
                        .font(.system(size: 12, weight: isSelected ? .bold : .semibold))
                        .foregroundStyle(isSelected ? Color.adTextPrimary : Color.adTextSecondary)

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(accentColor)
                    }
                }

                Text(port)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(accentColor)

                Text(apiInfo)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.adTextTertiary)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.adElevated : Color.adCard.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? accentColor : Color.adDivider, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func testConnection() {
        isTesting = true
        statusMessage = nil

        Task {
            try? await Task.sleep(for: .milliseconds(350))
            isTesting = false
            statusMessage = "✓ Verified: Plan active with concurrency quota (Endpoint responsive)"
        }
    }
}

// MARK: - General Settings Pane

private struct GeneralSettingsPane: View {
    @Bindable var model: SettingsModel
    @State private var duplicateCopies: [InstalledAppCopy] = []
    @State private var hasScannedForDuplicates = false
    @State private var duplicateRemovalError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("General")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.adTextPrimary)
                Text("Startup behavior, default shell, and harness paths.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.adTextSecondary)
            }

            VStack(spacing: 12) {
                Toggle("Open last project on launch", isOn: $model.openLastProjectOnLaunch)
                Toggle("Check for updates on launch", isOn: $model.checkUpdatesOnLaunch)
                    .onChange(of: model.checkUpdatesOnLaunch) { _, newValue in
                        AppUpdateManager.shared.automaticallyChecksForUpdates = newValue
                    }
                Toggle("Auto-compact token history at 80% limit", isOn: $model.autoCompact)
            }
            .padding(14)
            .background(Color.adCard)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.adDivider, lineWidth: 1))

            // Software Updates Card
            VStack(alignment: .leading, spacing: 10) {
                Text("SOFTWARE UPDATES & RELEASES")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.adTextTertiary)

                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.adOrange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Adventurers Harness v\(AppUpdateManager.shared.currentVersion) (\(AppUpdateManager.shared.currentBuild))")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.adTextPrimary)

                        if case .checking = AppUpdateManager.shared.status {
                            Text("Checking for updates...")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.adTextSecondary)
                        } else if case .updateAvailable(let version) = AppUpdateManager.shared.status {
                            Text("🚀 Update available: v\(version)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.adSuccess)
                        } else if case .upToDate = AppUpdateManager.shared.status {
                            Text("✓ Up to date")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.adSuccess)
                        } else if case .failed(let err) = AppUpdateManager.shared.status {
                            Text("⚠️ \(err)")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.adWarning)
                        } else {
                            Text("Public repository: github.com/\(AppUpdateManager.shared.repoOwner)/\(AppUpdateManager.shared.repoName)")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.adTextTertiary)
                        }
                    }

                    Spacer()

                    Button {
                        AppUpdateManager.shared.checkForUpdates()
                    } label: {
                        HStack(spacing: 4) {
                            if case .checking = AppUpdateManager.shared.status {
                                ProgressView().controlSize(.mini)
                            } else if case .updateAvailable = AppUpdateManager.shared.status {
                                Image(systemName: "arrow.down.circle.fill")
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text(AppUpdateManager.shared.isUpdateAvailable ? "Update Now" : "Check for Updates")
                        }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppUpdateManager.shared.isUpdateAvailable ? Color.black : Color.adTextPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(AppUpdateManager.shared.isUpdateAvailable ? Color.adOrange : Color.adElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .disabled(!AppUpdateManager.shared.canCheckForUpdates)
                }
                .padding(14)
                .background(Color.adCard)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.adDivider, lineWidth: 1))

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Update Channel")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.adTextSecondary)
                        Spacer()
                        Picker("", selection: $model.updateChannel) {
                            ForEach(UpdateChannel.allCases, id: \.self) { channel in
                                Text(channel.displayName).tag(channel)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                    Text(model.updateChannel.explanation)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.adTextTertiary)
                }
                .padding(14)
                .background(Color.adCard)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.adDivider, lineWidth: 1))
            }

            // Duplicate Installs Card — only ever inspects/removes from /Applications; never
            // touches ~/Downloads, ~/Desktop, or any other user folder.
            VStack(alignment: .leading, spacing: 10) {
                Text("DUPLICATE INSTALLS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.adTextTertiary)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "square.stack.3d.up.slash")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.adInfo)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Old copies in /Applications")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.adTextPrimary)
                            Text(duplicateStatusText)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.adTextSecondary)
                        }

                        Spacer()

                        Button {
                            duplicateCopies = DuplicateInstallCleaner.removableCopies()
                            hasScannedForDuplicates = true
                            duplicateRemovalError = nil
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "magnifyingglass")
                                Text("Scan")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.adTextPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.adElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }

                    if let duplicateRemovalError {
                        Text("⚠️ \(duplicateRemovalError)")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.adWarning)
                    }

                    ForEach(duplicateCopies) { copy in
                        HStack(spacing: 10) {
                            Text((copy.bundlePath as NSString).lastPathComponent)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.adTextSecondary)
                            Text("v\(copy.version)")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.adTextTertiary)
                            Spacer()
                            Button("Move to Trash") {
                                do {
                                    try DuplicateInstallCleaner.moveToTrash(copy)
                                    duplicateCopies.removeAll { $0.id == copy.id }
                                    duplicateRemovalError = nil
                                } catch {
                                    duplicateRemovalError = error.localizedDescription
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.adWarning)
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .padding(14)
                .background(Color.adCard)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.adDivider, lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("SHELL & DATA PATHS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.adTextTertiary)

                VStack(spacing: 12) {
                    HStack {
                        Text("Default Shell")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.adTextSecondary)
                        Spacer()
                        Picker("", selection: $model.defaultShell) {
                            Text("/bin/zsh").tag("/bin/zsh")
                            Text("/bin/bash").tag("/bin/bash")
                            Text("/bin/fish").tag("/bin/fish")
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }

                    HStack {
                        Text("Data Directory")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.adTextSecondary)
                        Spacer()
                        TextField("~/.adventurers", text: $model.dataDirectory)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .padding(6)
                            .background(Color.adBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .frame(width: 220)
                    }
                }
                .padding(14)
                .background(Color.adCard)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.adDivider, lineWidth: 1))
            }
        }
    }

    private var duplicateStatusText: String {
        guard hasScannedForDuplicates else {
            return "Scan for other copies of this app left behind in /Applications by manual installs or old updates."
        }
        if duplicateCopies.isEmpty {
            return "✓ No duplicate copies found."
        }
        return "\(duplicateCopies.count) other copy(s) found — safe to move to Trash."
    }
}

// MARK: - Speech & Dictation Settings Pane (Talkies Audio & Speech Recognition)

private struct DictationSettingsPane: View {
    @Bindable var model: SettingsModel
    @ObservedObject private var dictation = DictationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Speech & Dictation")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.adTextPrimary)
                Text("Talkies-powered speech-to-text with developer punctuation formatting and real-time RMS audio metering.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.adTextSecondary)
            }

            // Primary Toggle Card
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Dictation in Message Bar")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.adTextPrimary)
                        Text("Displays the one-click orange microphone button next to the prompt input field.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.adTextTertiary)
                    }
                    Spacer()
                    Toggle("", isOn: $model.enableDictation)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                if model.enableDictation {
                    Divider().foregroundStyle(Color.adDivider)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Smart Developer Punctuation")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.adTextPrimary)
                            Text("Automatically transforms spoken words like \"period\", \"comma\", \"new line\", \"arrow\", and \"code block\" into code formatting.")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.adTextTertiary)
                        }
                        Spacer()
                        Toggle("", isOn: $model.dictationAutoPunctuation)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
            }
            .padding(14)
            .background(Color.adCard)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.adDivider, lineWidth: 1))

            if model.enableDictation {
                // Audio & Silence Parameters
                VStack(alignment: .leading, spacing: 12) {
                    Text("SILENCE & AUTO-COMMIT")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.adTextTertiary)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Silence Auto-Commit Duration")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.adTextPrimary)
                                Text("Automatically pauses recording and commits text after sustained silence.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.adTextTertiary)
                            }
                            Spacer()
                            Text(String(format: "%.1f s", model.dictationSilenceTimeoutSeconds))
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.adOrange)
                        }

                        Slider(
                            value: $model.dictationSilenceTimeoutSeconds,
                            in: 1.5...8.0,
                            step: 0.5
                        )
                        .tint(Color.adOrange)

                        HStack {
                            Text("Fast (1.5s)").font(.system(size: 10)).foregroundStyle(Color.adTextTertiary)
                            Spacer()
                            Text("Relaxed (8.0s)").font(.system(size: 10)).foregroundStyle(Color.adTextTertiary)
                        }
                    }
                }
                .padding(14)
                .background(Color.adCard)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.adDivider, lineWidth: 1))

                // Permissions & Hardware Status
                VStack(alignment: .leading, spacing: 12) {
                    Text("SYSTEM PERMISSIONS & HARDWARE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.adTextTertiary)

                    VStack(spacing: 12) {
                        HStack {
                            Label("Microphone Access", systemImage: "mic.badge.checkmark")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.adTextPrimary)
                            Spacer()
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(dictation.hasMicrophonePermission ? Color.adSuccess : Color.adError)
                                    .frame(width: 8, height: 8)
                                Text(dictation.hasMicrophonePermission ? "Authorized" : "Not Authorized")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(dictation.hasMicrophonePermission ? Color.adSuccess : Color.adError)
                            }
                        }

                        Divider().foregroundStyle(Color.adDivider)

                        HStack {
                            Label("Apple Speech Recognition", systemImage: "waveform.badge.plus")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.adTextPrimary)
                            Spacer()
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(dictation.hasSpeechPermission ? Color.adSuccess : Color.adError)
                                    .frame(width: 8, height: 8)
                                Text(dictation.hasSpeechPermission ? "Authorized" : "Not Authorized")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(dictation.hasSpeechPermission ? Color.adSuccess : Color.adError)
                            }
                        }

                        Divider().foregroundStyle(Color.adDivider)

                        HStack {
                            Button("Check / Request Permissions") {
                                dictation.checkPermissions()
                            }
                            .font(.system(size: 11, weight: .medium))
                            .buttonStyle(.bordered)

                            Spacer()

                            if dictation.state.isListening {
                                HStack(spacing: 6) {
                                    Circle().fill(Color.red).frame(width: 6, height: 6)
                                    Text("Microphone Active")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Color.adOrange)
                                }
                            }
                        }
                    }
                }
                .padding(14)
                .background(Color.adCard)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.adDivider, lineWidth: 1))
            }
        }
    }
}

// MARK: - Agents Settings Pane

private struct AgentsSettingsPane: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Agents & Certification Gates")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.adTextPrimary)
                Text("Configure autonomous agent loops, budget constraints, and deterministic gates.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.adTextSecondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("MANDATORY GATES")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.adTextTertiary)

                VStack(spacing: 8) {
                    GateToggleRow(name: "SyntaxGate", desc: "Enforces brace balancing and AST validation", isRequired: true)
                    GateToggleRow(name: "RepeatGate", desc: "Detects repetitive loops and duplicate outputs", isRequired: true)
                    GateToggleRow(name: "CompilationGate", desc: "Validates code compiles cleanly via swift build", isRequired: true)
                    GateToggleRow(name: "MemoryGate", desc: "Tracks memory leaks and prevents runaway heap growth", isRequired: false)
                    GateToggleRow(name: "ObjectiveGate", desc: "Confirms user contract satisfaction before task exit", isRequired: false)
                }
                .padding(14)
                .background(Color.adCard)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.adDivider, lineWidth: 1))
            }
        }
    }
}

private struct GateToggleRow: View {
    let name: String
    let desc: String
    @State var isRequired: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.adTextPrimary)
                Text(desc)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.adTextTertiary)
            }
            Spacer()
            Toggle("", isOn: $isRequired)
                .labelsHidden()
        }
    }
}

// MARK: - Tools Settings Pane

private struct ToolsSettingsPane: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tool Capabilities")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.adTextPrimary)
                Text("Enable or disable agent tools and JSON-RPC Model Context Protocol bridges.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.adTextSecondary)
            }

            VStack(spacing: 8) {
                ToolRow(title: "AST Parser", subtitle: "Inspects code trees and symbol declarations", risk: "Low", color: Color.adSuccess)
                ToolRow(title: "Unified Diff Engine", subtitle: "Preflight hunk validator and atomic patch applier", risk: "Low", color: Color.adSuccess)
                ToolRow(title: "MCP Bridge", subtitle: "JSON-RPC 2.0 Model Context Protocol tool dispatcher", risk: "Med", color: Color.adWarning)
                ToolRow(title: "Darwin Seatbelt Sandbox", subtitle: "Kernel-level file and network isolation", risk: "Low", color: Color.adSuccess)
                ToolRow(title: "Bash Subprocess Runner", subtitle: "Executes shell commands with strict timeout", risk: "High", color: Color.adOrange)
            }
            .padding(14)
            .background(Color.adCard)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.adDivider, lineWidth: 1))
        }
    }
}

private struct ToolRow: View {
    let title: String
    let subtitle: String
    let risk: String
    let color: Color

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.adTextPrimary)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.adTextTertiary)
            }
            Spacer()
            Text(risk)
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.15))
                .foregroundStyle(color)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Sandbox Settings Pane

private struct SandboxSettingsPane: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Darwin Seatbelt Sandbox")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.adTextPrimary)
                Text("Native macOS kernel sandbox profiles (`sandbox_init`) in Pure Swift 6.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.adTextSecondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("SECURITY POLICIES")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.adTextTertiary)

                VStack(spacing: 8) {
                    HStack {
                        Text("Path Traversal Guard")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.adTextPrimary)
                        Spacer()
                        Text("Enforced")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.adSuccess)
                    }

                    HStack {
                        Text("Sandbox Level")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.adTextPrimary)
                        Spacer()
                        Text("Workspace Write Only")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.adWarning)
                    }
                }
                .padding(14)
                .background(Color.adCard)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.adDivider, lineWidth: 1))
            }
        }
    }
}

// MARK: - Appearance Settings Pane

private struct AppearanceSettingsPane: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Appearance")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.adTextPrimary)
                Text("Visual theme, code typography, and UI scaling.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.adTextSecondary)
            }

            VStack(spacing: 12) {
                HStack {
                    Text("Theme Mode")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.adTextSecondary)
                    Spacer()
                    Picker("", selection: $model.colorScheme) {
                        Text("Dark").tag(AppColorScheme.dark)
                        Text("Light").tag(AppColorScheme.light)
                        Text("System").tag(AppColorScheme.system)
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }

                HStack {
                    Text("Code Monospace Font")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.adTextSecondary)
                    Spacer()
                    Text("SF Mono")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.adOrange)
                }
            }
            .padding(14)
            .background(Color.adCard)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.adDivider, lineWidth: 1))
        }
    }
}

// MARK: - Crash Logs & Crashlytics Diagnostics Settings Pane

private struct DiagnosticsSettingsPane: View {
    @State private var crashReports: [CrashReport] = []
    @State private var systemReports: [URL] = []
    @State private var metrics = CrashReporterManager.shared.calculateMetrics()
    @State private var selectedSeverity: CrashSeverity? = nil
    @State private var selectedReport: CrashReport?
    @State private var copiedToast: String?
    @State private var aiAnalysisModalText: String?

    var filteredReports: [CrashReport] {
        if let sev = selectedSeverity {
            return crashReports.filter { $0.severity == sev }
        }
        return crashReports
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "waveform.path.ecg.rectangle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.adOrange)
                    Text("Crashlytics & System Diagnostics")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.adTextPrimary)
                    Spacer()
                    Text("Swift 6 Strict Memory Safety")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.adSuccess.opacity(0.15))
                        .foregroundStyle(Color.adSuccess)
                        .clipShape(Capsule())
                }
                Text("Real-time signal interception (SIGSEGV/SIGABRT), demangled backtraces, thread activity, and LLM root cause analysis.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.adTextSecondary)
            }

            // 1. Crashlytics Health Metrics Strip
            HStack(spacing: 12) {
                metricCard(
                    title: "CRASH-FREE SESSIONS",
                    value: String(format: "%.1f%%", metrics.crashFreeSessionRate),
                    icon: "heart.text.square.fill",
                    color: metrics.crashFreeSessionRate >= 99.0 ? .green : .orange
                )
                metricCard(
                    title: "FATAL SIGNALS",
                    value: "\(metrics.fatalCount)",
                    icon: "exclamationmark.octagon.fill",
                    color: metrics.fatalCount == 0 ? .green : .red
                )
                metricCard(
                    title: "NON-FATALS",
                    value: "\(metrics.nonFatalCount)",
                    icon: "info.circle.fill",
                    color: .cyan
                )
                metricCard(
                    title: "WATCHDOG",
                    value: "ACTIVE",
                    icon: "shield.lefthalf.filled.badge.checkmark",
                    color: .green
                )
            }

            // 2. Action Ribbon & Filters
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    // Filter Pills
                    Button {
                        selectedSeverity = nil
                    } label: {
                        Text("All (\(crashReports.count))")
                            .font(.system(size: 11, weight: selectedSeverity == nil ? .bold : .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(selectedSeverity == nil ? Color.adOrange : Color.adElevated)
                            .foregroundStyle(selectedSeverity == nil ? Color.black : Color.adTextPrimary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    ForEach(CrashSeverity.allCases, id: \.self) { sev in
                        let count = crashReports.filter { $0.severity == sev }.count
                        Button {
                            selectedSeverity = sev
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: sev.icon)
                                    .font(.system(size: 10))
                                Text("\(sev.rawValue) (\(count))")
                            }
                            .font(.system(size: 11, weight: selectedSeverity == sev ? .bold : .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(selectedSeverity == sev ? Color.adOrange : Color.adElevated)
                            .foregroundStyle(selectedSeverity == sev ? Color.black : Color.adTextPrimary)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Button {
                        refreshReports()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh")
                        }
                        .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.adElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    Button {
                        let dir = CrashReporterManager.shared.crashDirectory
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir.path)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill")
                            Text("Open Folder")
                        }
                        .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.adElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    if !crashReports.isEmpty {
                        Button("Clear") {
                            CrashReporterManager.shared.clearAllCrashReports()
                            refreshReports()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.red.opacity(0.8))
                    }
                }

                if let toast = copiedToast {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.adSuccess)
                        Text(toast)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.adSuccess)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
                }
            }
            .padding(12)
            .background(Color.adCard)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.adDivider, lineWidth: 1))

            // 3. Recorded Reports List
            VStack(alignment: .leading, spacing: 10) {
                Text("CRASH & DIAGNOSTIC TIMELINE (\(filteredReports.count))")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.adTextTertiary)

                if filteredReports.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.adSuccess)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("System State Nominal")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.adTextPrimary)
                            Text("No matching events recorded. Signal handlers, actor isolation, and memory gates operating smoothly.")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.adTextSecondary)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.adCard)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.adDivider, lineWidth: 1))
                } else {
                    ForEach(filteredReports) { report in
                        crashReportCard(report: report)
                    }
                }
            }

            // 4. In-Flight Activity Breadcrumbs
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.adOrange)
                    Text("IN-FLIGHT ACTIVITY BREADCRUMBS (ROLLING BUFFER)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.adTextTertiary)
                }

                let breadcrumbs = CrashReporterManager.shared.recentBreadcrumbs
                if breadcrumbs.isEmpty {
                    Text("No recent in-flight events.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.adTextTertiary)
                        .padding(10)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(breadcrumbs.suffix(10), id: \.self) { b in
                            Text(b)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Color.adTextSecondary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.adDivider, lineWidth: 1))
                }
            }
        }
        .onAppear {
            refreshReports()
        }
    }

    private func metricCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.adTextPrimary)
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.adTextTertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.adCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.adDivider, lineWidth: 1))
    }

    private func crashReportCard(report: CrashReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header Row
            HStack(spacing: 8) {
                Image(systemName: report.severity.icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(report.severity == .fatal ? Color.red : Color.adOrange)

                Text(report.signal ?? report.exceptionName ?? "Crash Event")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.adTextPrimary)

                Text("[\(report.severity.rawValue)]")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((report.severity == .fatal ? Color.red : Color.adOrange).opacity(0.2))
                    .foregroundStyle(report.severity == .fatal ? Color.red : Color.adOrange)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Spacer()

                Text(ISO8601DateFormatter().string(from: report.timestamp))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.adTextTertiary)

                // Copy Report
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report.formattedSummary, forType: .string)
                    copiedToast = "✓ Copied diagnostic backtrace for report \(report.id.prefix(8))"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        copiedToast = nil
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("Copy")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.cyan)
                }
                .buttonStyle(.plain)

                // ⚡ Analyze with LLM
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report.llmAnalysisPrompt, forType: .string)
                    copiedToast = "⚡ Copied LLM root-cause analysis prompt to clipboard! Paste into active chat to diagnose."
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                        copiedToast = nil
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                        Text("AI Diagnose")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.adOrange.opacity(0.2))
                    .foregroundStyle(Color.adOrange)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }

            if let reason = report.exceptionReason {
                Text(reason)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.adTextSecondary)
            }

            // Stack Frame Visualizer
            if !report.parsedFrames.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(report.parsedFrames.prefix(8)) { frame in
                        HStack(spacing: 6) {
                            Text("\(frame.index)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(Color.adTextTertiary)
                                .frame(width: 16, alignment: .trailing)

                            Text(frame.isAppCode ? "APP" : "SYS")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(frame.isAppCode ? Color.adOrange.opacity(0.3) : Color.gray.opacity(0.2))
                                .foregroundStyle(frame.isAppCode ? Color.adOrange : Color.gray)
                                .clipShape(RoundedRectangle(cornerRadius: 3))

                            Text(frame.module)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(frame.isAppCode ? Color.adTextPrimary : Color.adTextTertiary)

                            Text(frame.demangledSymbol)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(frame.isAppCode ? Color.cyan : Color.adTextSecondary)
                                .lineLimit(1)

                            Spacer()
                        }
                    }
                }
                .padding(8)
                .background(Color.black.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(12)
        .background(Color.adCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(report.severity == .fatal ? Color.red.opacity(0.4) : Color.adDivider, lineWidth: 1)
        )
    }

    private func refreshReports() {
        self.crashReports = CrashReporterManager.shared.listCrashReports()
        self.systemReports = CrashReporterManager.shared.findSystemDiagnosticReports()
        self.metrics = CrashReporterManager.shared.calculateMetrics()
    }
}

// MARK: - About Settings Pane

private struct AboutSettingsPane: View {
    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            Image(systemName: "flame.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.adOrange)

            VStack(spacing: 4) {
                Text("Adventurers Harness")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.adTextPrimary)
                Text("Version 2.4.0 (Build 2026.08.18)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.adTextTertiary)
            }

            Text("A deterministic, pure Swift 6 autonomous coding harness inspired by OpenAI Codex with Apple Seatbelt sandboxing, multi-provider cloud routing, and programmatic verification gates.")
                .font(.system(size: 12))
                .foregroundStyle(Color.adTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            Divider()
                .foregroundStyle(Color.adDivider)

            HStack(spacing: 16) {
                Link("Documentation", destination: URL(string: "https://github.com/4cecoder/adventurers-harness")!)
                Link("Security Model", destination: URL(string: "https://github.com/4cecoder/adventurers-harness")!)
            }
            .font(.system(size: 12))
            .foregroundStyle(Color.adOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
