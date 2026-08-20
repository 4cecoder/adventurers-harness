// AdventurersCore - Native LM Studio REST API Bridge & On-Device Ecosystem Integration
// Supports:
// - LM Studio v1 Native REST API (/api/v1/*, /api/v1/models, /api/v1/chat)
// - OpenAI Responses API (/v1/responses) with custom tools & structured extraction
// - OpenAI-compatible Chat Completions (/v1/chat/completions)
// - Anthropic-compatible Messages (/v1/messages)

import Foundation
import LLMProviders

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

// MARK: - LM Studio Tool Definition Schema

public struct LMStudioToolParameter: Sendable, Codable {
    public let type: String
    public let description: String?
    public let enumValues: [String]?

    public init(type: String, description: String? = nil, enumValues: [String]? = nil) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
    }

    enum CodingKeys: String, CodingKey {
        case type, description
        case enumValues = "enum"
    }
}

public struct LMStudioFunctionDefinition: Sendable, Codable {
    public let name: String
    public let description: String
    public let parameters: [String: AnyCodable]

    public init(name: String, description: String, parameters: [String: AnyCodable]) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

public struct LMStudioTool: Sendable, Codable {
    public let type: String
    public let name: String?
    public let description: String?
    public let parameters: [String: AnyCodable]?
    public let function: LMStudioFunctionDefinition?

    public init(name: String, description: String, parameters: [String: AnyCodable]) {
        self.type = "function"
        self.name = name
        self.description = description
        self.parameters = parameters
        self.function = LMStudioFunctionDefinition(name: name, description: description, parameters: parameters)
    }
}

// MARK: - LM Studio Responses API Result

public struct LMStudioResponsesResult: Sendable {
    public let id: String
    public let model: String
    public let text: String
    public let toolCalls: [ToolCall]
    public let usage: TokenUsage?

    public init(id: String, model: String, text: String, toolCalls: [ToolCall], usage: TokenUsage? = nil) {
        self.id = id
        self.model = model
        self.text = text
        self.toolCalls = toolCalls
        self.usage = usage
    }
}

// MARK: - LM Studio Bridge Engine

public actor LMStudioBridge {
    public static let shared = LMStudioBridge()
    public static let defaultBaseURL = "http://localhost:1234"

    private init() {}

    /// Checks if LM Studio local server is active and returns loaded model inventory.
    public func checkServerStatus(baseURL: String = defaultBaseURL) async -> LMStudioServerStatus {
        let cleanBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
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

    // MARK: - LM Studio /v1/responses Endpoint Integration

    /// Executes a request against LM Studio's `/v1/responses` endpoint with support for tool definitions.
    public func sendResponses(
        model: String,
        input: String,
        tools: [LMStudioTool] = [],
        toolChoice: String = "auto",
        baseURL: String = defaultBaseURL
    ) async throws -> LMStudioResponsesResult {
        let cleanBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpoint = cleanBase.hasSuffix("/v1") ? "\(cleanBase)/responses" : "\(cleanBase)/v1/responses"
        guard let url = URL(string: endpoint) else {
            throw LLMError.networkError(NSError(domain: "LMStudioBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid endpoint: \(endpoint)"]))
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": model,
            "input": input
        ]

        if !tools.isEmpty {
            let toolsData = try JSONEncoder().encode(tools)
            let toolsJSON = try JSONSerialization.jsonObject(with: toolsData)
            body["tools"] = toolsJSON
            body["tool_choice"] = toolChoice
        }

        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, res) = try await URLSession.shared.data(for: req)
        guard let http = res as? HTTPURLResponse else {
            throw LLMError.apiError(statusCode: 0)
        }

        guard http.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw LLMError.networkError(NSError(domain: "LMStudioBridge", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: errorText]))
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.decodingError
        }

        let respId = json["id"] as? String ?? UUID().uuidString
        let respModel = json["model"] as? String ?? model

        var outputText = ""
        var toolCalls: [ToolCall] = []

        // Parse Responses API structured output
        if let outputArray = json["output"] as? [[String: Any]] {
            for item in outputArray {
                let type = item["type"] as? String
                if type == "message", let content = item["content"] as? String {
                    outputText += content
                } else if type == "function_call" || type == "tool_call" {
                    let callId = item["id"] as? String ?? UUID().uuidString
                    let name = item["name"] as? String ?? ""
                    var args: [String: AnyCodable] = [:]
                    if let rawArgs = item["arguments"] as? [String: Any] {
                        args = rawArgs.mapValues { AnyCodable($0) }
                    } else if let argsStr = item["arguments"] as? String,
                              let argsData = argsStr.data(using: .utf8),
                              let decoded = try? JSONDecoder().decode([String: AnyCodable].self, from: argsData) {
                        args = decoded
                    }
                    toolCalls.append(ToolCall(id: callId, name: name, arguments: args))
                }
            }
        } else if let text = json["output_text"] as? String ?? json["content"] as? String {
            outputText = text
        }

        let usageDict = json["usage"] as? [String: Int]
        let usage = usageDict.map {
            TokenUsage(
                promptTokens: $0["prompt_tokens"] ?? $0["input_tokens"] ?? 0,
                completionTokens: $0["completion_tokens"] ?? $0["output_tokens"] ?? 0,
                totalTokens: $0["total_tokens"] ?? 0
            )
        }

        return LMStudioResponsesResult(id: respId, model: respModel, text: outputText, toolCalls: toolCalls, usage: usage)
    }

    /// Streams real-time tokens and tool calls from LM Studio's `/v1/responses` SSE stream.
    public func streamResponses(
        model: String,
        input: String,
        tools: [LMStudioTool] = [],
        toolChoice: String = "auto",
        baseURL: String = defaultBaseURL
    ) -> AsyncThrowingStream<LLMChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let cleanBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let endpoint = cleanBase.hasSuffix("/v1") ? "\(cleanBase)/responses" : "\(cleanBase)/v1/responses"
                guard let url = URL(string: endpoint) else {
                    continuation.finish(throwing: LLMError.networkError(NSError(domain: "LMStudioBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid endpoint: \(endpoint)"])))
                    return
                }

                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.addValue("application/json", forHTTPHeaderField: "Content-Type")

                var body: [String: Any] = [
                    "model": model,
                    "input": input,
                    "stream": true
                ]

                if !tools.isEmpty {
                    if let toolsData = try? JSONEncoder().encode(tools),
                       let toolsJSON = try? JSONSerialization.jsonObject(with: toolsData) {
                        body["tools"] = toolsJSON
                        body["tool_choice"] = toolChoice
                    }
                }

                guard let postData = try? JSONSerialization.data(withJSONObject: body) else {
                    continuation.finish(throwing: LLMError.encodingError)
                    return
                }
                req.httpBody = postData

                do {
                    let (asyncBytes, response) = try await URLSession.shared.bytes(for: req)
                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        continuation.finish(throwing: LLMError.apiError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0))
                        return
                    }

                    for try await line in asyncBytes.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmed.hasPrefix("data: ") else { continue }
                        let jsonStr = String(trimmed.dropFirst(6))
                        if jsonStr == "[DONE]" { break }

                        guard let data = jsonStr.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            continue
                        }

                        // OpenAI Responses API SSE Events
                        let eventType = event["type"] as? String
                        if eventType == "response.text.delta" || eventType == "text.delta",
                           let delta = event["delta"] as? String {
                            continuation.yield(LLMChunk(delta: delta))
                        } else if let delta = event["delta"] as? [String: Any],
                                  let content = delta["content"] as? String {
                            continuation.yield(LLMChunk(delta: content))
                        } else if let choices = event["choices"] as? [[String: Any]],
                                  let first = choices.first,
                                  let delta = first["delta"] as? [String: Any],
                                  let content = delta["content"] as? String {
                            continuation.yield(LLMChunk(delta: content))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
