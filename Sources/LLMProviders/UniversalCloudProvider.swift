// Sources/LLMProviders/UniversalCloudProvider.swift
// Adventurers Standalone Universal Multi-Cloud LLM Provider Adapter
//
// Completely decoupled native implementation supporting:
// - Anthropic Messages API (Claude 3.7 Sonnet, Extended Thinking, Streaming SSE)
// - DeepSeek Native API (DeepSeek-V3 & DeepSeek-R1 with reasoning_content)
// - Zhipu / Z.AI GLM Coding Plan API (GLM-5.3, GLM-5.2, GLM-4.7)
// - OpenAI Native API (GPT-4o, o1, o3-mini)
// - OpenRouter Unified Multi-Model Gateway
// - Local Inference (Ollama, vLLM, LM Studio)
//
// Zero dependency on external CLI runners. Pure Swift 6 Sendable streaming.

import Foundation

public struct UniversalCloudProvider: LLMProvider, Sendable {
    public let name: String
    public let supportsConversations = true

    public let apiKey: String
    public let baseURL: String
    public let isAnthropicNative: Bool

    public init(
        name: String = "Universal Cloud",
        apiKey: String,
        baseURL: String,
        isAnthropicNative: Bool = false
    ) {
        self.name = name
        self.apiKey = apiKey
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.isAnthropicNative = isAnthropicNative
    }

    // MARK: - Unary Execution

    public func send(messages: [Message], config: LLMConfig) async throws -> LLMResponse {
        if isAnthropicNative || baseURL.contains("api.anthropic.com") {
            return try await sendAnthropic(messages: messages, config: config)
        } else {
            return try await sendOpenAICompatible(messages: messages, config: config)
        }
    }

    // MARK: - Streaming Execution

    public func stream(messages: [Message], config: LLMConfig) -> AsyncThrowingStream<LLMChunk, Error> {
        if isAnthropicNative || baseURL.contains("api.anthropic.com") {
            return streamAnthropic(messages: messages, config: config)
        } else {
            return streamOpenAICompatible(messages: messages, config: config)
        }
    }

    // MARK: - OpenAI / DeepSeek / Z.AI GLM / OpenRouter Native Protocol

    private func sendOpenAICompatible(messages: [Message], config: LLMConfig) async throws -> LLMResponse {
        let endpoint = baseURL.hasSuffix("/chat/completions") ? baseURL : "\(baseURL)/chat/completions"
        guard let url = URL(string: endpoint) else {
            throw LLMError.networkError(NSError(domain: "UniversalCloud", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid endpoint URL: \(endpoint)"]))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        // OpenRouter Attribution Headers
        if baseURL.contains("openrouter.ai") {
            request.addValue("https://github.com/adventurers-harness", forHTTPHeaderField: "HTTP-Referer")
            request.addValue("Adventurers Native Agent Harness", forHTTPHeaderField: "X-Title")
        }

        var body: [String: Any] = [
            "model": config.model,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "temperature": config.temperature ?? 0.2,
            "max_tokens": config.maxTokens ?? 4096,
        ]

        // Reasoning models support (DeepSeek R1 / GLM Thinking / o1)
        if config.model.contains("reasoner") || config.model.contains("r1") || config.model.contains("glm") {
            body["max_tokens"] = max(config.maxTokens ?? 4096, 8192)
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.apiError(statusCode: 0)
        }

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw LLMError.networkError(NSError(domain: "UniversalCloud", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorText]))
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            throw LLMError.decodingError
        }

        let content = message["content"] as? String ?? ""
        let reasoning = message["reasoning_content"] as? String

        let fullContent = reasoning != nil ? "<\(reasoning!)>\n\n\(content)" : content

        let usageDict = json["usage"] as? [String: Int]
        let usage = usageDict.map {
            TokenUsage(
                promptTokens: $0["prompt_tokens"] ?? 0,
                completionTokens: $0["completion_tokens"] ?? 0,
                totalTokens: $0["total_tokens"] ?? 0
            )
        }

        return LLMResponse(content: fullContent, toolCalls: [], usage: usage)
    }

    private func streamOpenAICompatible(messages: [Message], config: LLMConfig) -> AsyncThrowingStream<LLMChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let endpoint = baseURL.hasSuffix("/chat/completions") ? baseURL : "\(baseURL)/chat/completions"
                guard let url = URL(string: endpoint) else {
                    continuation.finish(throwing: LLMError.networkError(NSError(domain: "UniversalCloud", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL: \(endpoint)"])))
                    return
                }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")

                if baseURL.contains("openrouter.ai") {
                    request.addValue("https://github.com/adventurers-harness", forHTTPHeaderField: "HTTP-Referer")
                    request.addValue("Adventurers Native Agent Harness", forHTTPHeaderField: "X-Title")
                }

                var body: [String: Any] = [
                    "model": config.model,
                    "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
                    "temperature": config.temperature ?? 0.2,
                    "max_tokens": config.maxTokens ?? 4096,
                    "stream": true,
                    "stream_options": ["include_usage": true]
                ]

                if config.model.contains("reasoner") || config.model.contains("r1") || config.model.contains("glm") {
                    body["max_tokens"] = max(config.maxTokens ?? 4096, 8192)
                }

                do {
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: LLMError.apiError(statusCode: 0))
                        return
                    }

                    guard httpResponse.statusCode == 200 else {
                        var errBytes: [UInt8] = []
                        for try await b in bytes { errBytes.append(b) }
                        let errStr = String(bytes: errBytes, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
                        continuation.finish(throwing: LLMError.networkError(NSError(domain: "UniversalCloud", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error (\(httpResponse.statusCode)): \(errStr)"])))
                        return
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonStr = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
                        if jsonStr == "[DONE]" { break }

                        guard let data = jsonStr.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                        var chunkUsage: TokenUsage? = nil
                        if let usageDict = json["usage"] as? [String: Any] {
                            let p = usageDict["prompt_tokens"] as? Int ?? 0
                            let c = usageDict["completion_tokens"] as? Int ?? 0
                            let t = usageDict["total_tokens"] as? Int ?? (p + c)
                            chunkUsage = TokenUsage(promptTokens: p, completionTokens: c, totalTokens: t)
                        }

                        let choices = json["choices"] as? [[String: Any]]
                        let delta = choices?.first?["delta"] as? [String: Any]

                        let content = delta?["content"] as? String ?? ""
                        let reasoning = delta?["reasoning_content"] as? String
                        let finishReason = choices?.first?["finish_reason"] as? String

                        if !content.isEmpty || reasoning != nil || chunkUsage != nil {
                            continuation.yield(LLMChunk(
                                delta: content,
                                reasoningDelta: reasoning,
                                toolCalls: nil,
                                finishReason: finishReason,
                                usage: chunkUsage
                            ))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Anthropic Native Messages API Protocol (SSE Streaming)

    private func sendAnthropic(messages: [Message], config: LLMConfig) async throws -> LLMResponse {
        let endpoint = baseURL.hasSuffix("/messages") ? baseURL : "\(baseURL)/messages"
        guard let url = URL(string: endpoint) else {
            throw LLMError.networkError(NSError(domain: "Anthropic", code: -1, userInfo: nil))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // Handle both standard API keys and OAuth Bearer tokens
        if apiKey.hasPrefix("sk-ant-oat") || apiKey.contains("Bearer ") {
            let token = apiKey.replacingOccurrences(of: "Bearer ", with: "")
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        }
        
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n\n")
        let nonSystemMessages = messages.filter { $0.role != .system }

        var body: [String: Any] = [
            "model": config.model,
            "messages": nonSystemMessages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "max_tokens": config.maxTokens ?? 4096,
            "temperature": config.temperature ?? 0.2,
        ]
        
        if !systemPrompt.isEmpty {
            body["system"] = systemPrompt
        }

        // Support Claude 3.7 Extended Thinking
        if config.model.contains("3-7") || config.model.contains("thinking") {
            body["thinking"] = [
                "type": "enabled",
                "budget_tokens": 2048
            ]
            body["temperature"] = 1.0 // Required when thinking is enabled
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"
            throw LLMError.networkError(NSError(domain: "Anthropic", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: errorText]))
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentBlocks = json["content"] as? [[String: Any]] else {
            throw LLMError.decodingError
        }

        var fullText = ""
        for block in contentBlocks {
            if let type = block["type"] as? String, type == "text", let text = block["text"] as? String {
                fullText += text
            } else if let type = block["type"] as? String, type == "thinking", let thinking = block["thinking"] as? String {
                fullText = "<\(thinking)>\n\n" + fullText
            }
        }

        let usageDict = json["usage"] as? [String: Int]
        let usage = usageDict.map {
            TokenUsage(
                promptTokens: $0["input_tokens"] ?? 0,
                completionTokens: $0["output_tokens"] ?? 0,
                totalTokens: ($0["input_tokens"] ?? 0) + ($0["output_tokens"] ?? 0)
            )
        }

        return LLMResponse(content: fullText, toolCalls: [], usage: usage)
    }

    private func streamAnthropic(messages: [Message], config: LLMConfig) -> AsyncThrowingStream<LLMChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let endpoint = baseURL.hasSuffix("/messages") ? baseURL : "\(baseURL)/messages"
                guard let url = URL(string: endpoint) else {
                    continuation.finish(throwing: LLMError.networkError(NSError(domain: "Anthropic", code: -1, userInfo: nil)))
                    return
                }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                
                if apiKey.hasPrefix("sk-ant-oat") || apiKey.contains("Bearer ") {
                    let token = apiKey.replacingOccurrences(of: "Bearer ", with: "")
                    request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                } else {
                    request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
                }
                
                request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")

                let systemPrompt = messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n\n")
                let nonSystemMessages = messages.filter { $0.role != .system }

                var body: [String: Any] = [
                    "model": config.model,
                    "messages": nonSystemMessages.map { ["role": $0.role.rawValue, "content": $0.content] },
                    "max_tokens": config.maxTokens ?? 4096,
                    "stream": true,
                ]
                
                if !systemPrompt.isEmpty {
                    body["system"] = systemPrompt
                }

                if config.model.contains("3-7") || config.model.contains("thinking") {
                    body["thinking"] = [
                        "type": "enabled",
                        "budget_tokens": 2048
                    ]
                } else {
                    body["temperature"] = config.temperature ?? 0.2
                }

                do {
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: LLMError.apiError(statusCode: 0))
                        return
                    }

                    guard httpResponse.statusCode == 200 else {
                        var errBytes: [UInt8] = []
                        for try await b in bytes { errBytes.append(b) }
                        let errStr = String(bytes: errBytes, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
                        continuation.finish(throwing: LLMError.networkError(NSError(domain: "Anthropic", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Anthropic API (\(httpResponse.statusCode)): \(errStr)"])))
                        return
                    }

                    var anthropicInputTokens = 0
                    var anthropicOutputTokens = 0

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonStr = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
                        if jsonStr.isEmpty { continue }

                        guard let data = jsonStr.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type = json["type"] as? String else { continue }

                        if type == "message_start", let msg = json["message"] as? [String: Any], let usage = msg["usage"] as? [String: Any] {
                            anthropicInputTokens = usage["input_tokens"] as? Int ?? 0
                        } else if type == "content_block_delta", let delta = json["delta"] as? [String: Any] {
                            let deltaType = delta["type"] as? String
                            if deltaType == "text_delta", let text = delta["text"] as? String {
                                continuation.yield(LLMChunk(delta: text))
                            } else if deltaType == "thinking_delta", let thinking = delta["thinking"] as? String {
                                continuation.yield(LLMChunk(delta: "", reasoningDelta: thinking))
                            }
                        } else if type == "message_delta", let usage = json["usage"] as? [String: Any] {
                            anthropicOutputTokens = usage["output_tokens"] as? Int ?? 0
                            let total = anthropicInputTokens + anthropicOutputTokens
                            let usageObj = TokenUsage(promptTokens: anthropicInputTokens, completionTokens: anthropicOutputTokens, totalTokens: total)
                            continuation.yield(LLMChunk(delta: "", usage: usageObj))
                        } else if type == "message_stop" {
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Model Discovery

    public func fetchAvailableModels() async throws -> [String] {
        let endpoint = baseURL.hasSuffix("/models") ? baseURL : "\(baseURL)/models"
        guard let url = URL(string: endpoint) else { return [] }
        var request = URLRequest(url: url)
        request.addValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        request.addValue("https://github.com/adventurers-harness", forHTTPHeaderField: "HTTP-Referer")
        request.addValue("Adventurers Native Harness", forHTTPHeaderField: "X-Title")

        if isAnthropicNative || baseURL.contains("api.anthropic.com") {
            if apiKey.hasPrefix("sk-ant-oat") || apiKey.contains("Bearer ") {
                let token = apiKey.replacingOccurrences(of: "Bearer ", with: "")
                request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            } else {
                request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
            }
            request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else {
            if !apiKey.isEmpty {
                let token = apiKey.replacingOccurrences(of: "Bearer ", with: "")
                request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        if let dataList = json["data"] as? [[String: Any]] {
            return dataList.compactMap { $0["id"] as? String ?? $0["name"] as? String }
        } else if let modelsList = json["models"] as? [[String: Any]] {
            return modelsList.compactMap { $0["name"] as? String ?? $0["id"] as? String }
        }
        return []
    }

    // MARK: - Conversation Management

    public func newConversation(system: String) async throws -> String {
        return UUID().uuidString
    }

    public func resume(conversationID: String, message: String) async throws -> String {
        let response = try await send(
            messages: [Message(role: .user, content: message)],
            config: LLMConfig(provider: name, model: "claude-3-7-sonnet", apiKey: apiKey)
        )
        return response.content
    }
}
