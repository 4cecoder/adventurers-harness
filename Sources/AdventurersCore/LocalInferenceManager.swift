// AdventurersCore - Unified Local Inference Engine Manager (LM Studio & Ollama)
// Instant on-device model discovery, health check probes, and 1-click toggling.

import Foundation

public enum LocalEngineType: String, CaseIterable, Sendable, Codable {
    case lmstudio = "LM Studio"
    case ollama = "Ollama"
    case custom = "Custom / vLLM"

    public var defaultPort: Int {
        switch self {
        case .lmstudio: return 1234
        case .ollama: return 11434
        case .custom: return 8000
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .lmstudio: return "http://localhost:1234/v1"
        case .ollama: return "http://localhost:11434/v1"
        case .custom: return "http://localhost:8000/v1"
        }
    }

    public var icon: String {
        switch self {
        case .lmstudio: return "laptopcomputer.and.arrow.down"
        case .ollama: return "cpu.fill"
        case .custom: return "server.rack"
        }
    }

    public var downloadURL: String {
        switch self {
        case .lmstudio: return "https://lmstudio.ai"
        case .ollama: return "https://ollama.com"
        case .custom: return "https://vllm.ai"
        }
    }
}

public struct LocalEngineStatus: Sendable, Equatable {
    public let engine: LocalEngineType
    public let isOnline: Bool
    public let baseURL: String
    public let discoveredModels: [String]
    public let statusMessage: String

    public init(
        engine: LocalEngineType,
        isOnline: Bool,
        baseURL: String,
        discoveredModels: [String] = [],
        statusMessage: String = ""
    ) {
        self.engine = engine
        self.isOnline = isOnline
        self.baseURL = baseURL
        self.discoveredModels = discoveredModels
        self.statusMessage = statusMessage
    }
}

public actor LocalInferenceManager {
    public static let shared = LocalInferenceManager()

    private init() {}

    /// Probes both LM Studio and Ollama to see which local engines are currently running on the machine.
    public func probeAllEngines() async -> [LocalEngineType: LocalEngineStatus] {
        var results: [LocalEngineType: LocalEngineStatus] = [:]

        // 1. Probe LM Studio
        let lmStatus = await probeLMStudio(baseURL: LocalEngineType.lmstudio.defaultBaseURL)
        results[.lmstudio] = lmStatus

        // 2. Probe Ollama
        let ollamaStatus = await probeOllama(baseURL: LocalEngineType.ollama.defaultBaseURL)
        results[.ollama] = ollamaStatus

        return results
    }

    public func probeLMStudio(baseURL: String = "http://localhost:1234/v1") async -> LocalEngineStatus {
        let cleanBase = baseURL.replacingOccurrences(of: "/v1", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(cleanBase)/api/v1/models") ?? URL(string: "\(cleanBase)/v1/models") else {
            return LocalEngineStatus(engine: .lmstudio, isOnline: false, baseURL: baseURL, statusMessage: "Invalid URL")
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = 1.5

        do {
            let (data, res) = try await URLSession.shared.data(for: req)
            guard let http = res as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return LocalEngineStatus(engine: .lmstudio, isOnline: false, baseURL: baseURL, statusMessage: "Server unreachable (Port 1234)")
            }

            var models: [String] = []
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let list = json["models"] as? [[String: Any]] {
                    models = list.compactMap { $0["id"] as? String ?? $0["name"] as? String }
                } else if let list = json["data"] as? [[String: Any]] {
                    models = list.compactMap { $0["id"] as? String }
                }
            }

            return LocalEngineStatus(
                engine: .lmstudio,
                isOnline: true,
                baseURL: baseURL,
                discoveredModels: models,
                statusMessage: "Online (Port 1234) · \(models.count) models available"
            )
        } catch {
            return LocalEngineStatus(engine: .lmstudio, isOnline: false, baseURL: baseURL, statusMessage: "Offline (Port 1234)")
        }
    }

    public func probeOllama(baseURL: String = "http://localhost:11434/v1") async -> LocalEngineStatus {
        let cleanBase = baseURL.replacingOccurrences(of: "/v1", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(cleanBase)/api/tags") ?? URL(string: "\(cleanBase)/v1/models") else {
            return LocalEngineStatus(engine: .ollama, isOnline: false, baseURL: baseURL, statusMessage: "Invalid URL")
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = 1.5

        do {
            let (data, res) = try await URLSession.shared.data(for: req)
            guard let http = res as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return LocalEngineStatus(engine: .ollama, isOnline: false, baseURL: baseURL, statusMessage: "Server unreachable (Port 11434)")
            }

            var models: [String] = []
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let list = json["models"] as? [[String: Any]] {
                    models = list.compactMap { $0["name"] as? String ?? $0["model"] as? String }
                } else if let list = json["data"] as? [[String: Any]] {
                    models = list.compactMap { $0["id"] as? String }
                }
            }

            return LocalEngineStatus(
                engine: .ollama,
                isOnline: true,
                baseURL: baseURL,
                discoveredModels: models,
                statusMessage: "Online (Port 11434) · \(models.count) models available"
            )
        } catch {
            return LocalEngineStatus(engine: .ollama, isOnline: false, baseURL: baseURL, statusMessage: "Offline (Port 11434)")
        }
    }
}
