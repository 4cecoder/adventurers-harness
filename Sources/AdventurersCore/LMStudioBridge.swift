// AdventurersCore - Native LM Studio REST API Bridge & On-Device Ecosystem Integration
// Supports LM Studio v1 Native REST API (/api/v1/*), OpenAI-compatible (/v1/chat/completions) & Anthropic (/v1/messages)

import Foundation

// MARK: - LM Studio Models & Status

public struct LMStudioModelInfo: Identifiable, Sendable, Codable {
    public let id: String
    public let name: String
    public let isLoaded: Bool
    public let architecture: String?
    public let quantization: String?
    public let contextLength: Int?
    public let sizeBytes: Int64?

    public init(
        id: String,
        name: String,
        isLoaded: Bool = false,
        architecture: String? = nil,
        quantization: String? = nil,
        contextLength: Int? = nil,
        sizeBytes: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.isLoaded = isLoaded
        self.architecture = architecture
        self.quantization = quantization
        self.contextLength = contextLength
        self.sizeBytes = sizeBytes
    }
}

public enum LMStudioServerStatus: Sendable, Equatable {
    case online(version: String, loadedModels: [String])
    case offline(reason: String)
}

// MARK: - LM Studio Bridge Actor

public actor LMStudioBridge {
    public static let shared = LMStudioBridge()
    public static let defaultBaseURL = "http://localhost:1234"

    private init() {}

    /// Checks if LM Studio local server is active and returns loaded model inventory.
    public func checkServerStatus(baseURL: String = defaultBaseURL) async -> LMStudioServerStatus {
        let cleanBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // First probe LM Studio native v1 API /api/v1/models
        guard let url = URL(string: "\(cleanBase)/api/v1/models") ?? URL(string: "\(cleanBase)/v1/models") else {
            return .offline(reason: "Invalid server URL")
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = 2.0

        do {
            let (data, res) = try await URLSession.shared.data(for: req)
            guard let http = res as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return .offline(reason: "Server returned HTTP \((res as? HTTPURLResponse)?.statusCode ?? 0)")
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .online(version: "v1", loadedModels: [])
            }

            var loaded: [String] = []
            if let modelsList = json["models"] as? [[String: Any]] {
                for m in modelsList {
                    if let id = m["id"] as? String ?? m["name"] as? String {
                        let isLoaded = m["loaded"] as? Bool ?? (m["state"] as? String == "loaded")
                        if isLoaded {
                            loaded.append(id)
                        }
                    }
                }
            } else if let dataList = json["data"] as? [[String: Any]] {
                for m in dataList {
                    if let id = m["id"] as? String {
                        loaded.append(id)
                    }
                }
            }

            return .online(version: "v1", loadedModels: loaded)
        } catch {
            return .offline(reason: error.localizedDescription)
        }
    }

    /// Discovers all downloaded and loaded models on the local LM Studio instance.
    public func listModels(baseURL: String = defaultBaseURL) async throws -> [LMStudioModelInfo] {
        let cleanBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var models: [LMStudioModelInfo] = []

        // Try LM Studio v1 REST API first: /api/v1/models
        if let v1Url = URL(string: "\(cleanBase)/api/v1/models") {
            var req = URLRequest(url: v1Url)
            req.timeoutInterval = 3.0
            if let (data, res) = try? await URLSession.shared.data(for: req),
               let http = res as? HTTPURLResponse, (200...299).contains(http.statusCode),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                if let modelsList = json["models"] as? [[String: Any]] {
                    for m in modelsList {
                        let id = m["id"] as? String ?? m["name"] as? String ?? "unknown"
                        let name = m["name"] as? String ?? id
                        let isLoaded = m["loaded"] as? Bool ?? (m["state"] as? String == "loaded")
                        let arch = m["architecture"] as? String
                        let quant = m["quantization"] as? String
                        let ctx = m["context_length"] as? Int ?? m["max_context_length"] as? Int
                        let size = m["size_bytes"] as? Int64
                        models.append(LMStudioModelInfo(
                            id: id,
                            name: name,
                            isLoaded: isLoaded,
                            architecture: arch,
                            quantization: quant,
                            contextLength: ctx,
                            sizeBytes: size
                        ))
                    }
                }
            }
        }

        // Fallback to OpenAI-compatible /v1/models if v1 models was empty
        if models.isEmpty, let openAIUrl = URL(string: "\(cleanBase)/v1/models") {
            var req = URLRequest(url: openAIUrl)
            req.timeoutInterval = 3.0
            if let (data, res) = try? await URLSession.shared.data(for: req),
               let http = res as? HTTPURLResponse, (200...299).contains(http.statusCode),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataList = json["data"] as? [[String: Any]] {
                for m in dataList {
                    let id = m["id"] as? String ?? "unknown"
                    models.append(LMStudioModelInfo(id: id, name: id, isLoaded: true))
                }
            }
        }

        return models
    }

    /// Loads a model into GPU memory via LM Studio v1 API.
    public func loadModel(id: String, baseURL: String = defaultBaseURL, contextLength: Int? = nil) async throws -> Bool {
        let cleanBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(cleanBase)/api/v1/models/load") else { return false }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = ["model": id]
        if let ctx = contextLength {
            body["context_length"] = ctx
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, res) = try await URLSession.shared.data(for: req)
        return (res as? HTTPURLResponse)?.statusCode == 200
    }

    /// Unloads a model from memory via LM Studio v1 API.
    public func unloadModel(id: String, baseURL: String = defaultBaseURL) async throws -> Bool {
        let cleanBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(cleanBase)/api/v1/models/unload") else { return false }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["model": id]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, res) = try await URLSession.shared.data(for: req)
        return (res as? HTTPURLResponse)?.statusCode == 200
    }
}
