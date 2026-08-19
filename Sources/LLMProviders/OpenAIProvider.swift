// LLMProviders - OpenAI API Client
// Direct HTTP client for OpenAI Responses API

import Foundation

/// OpenAI API provider implementation.
public struct OpenAIProvider: LLMProvider {
    public let name = "OpenAI"
    public let supportsConversations = true

    private let apiKey: String
    private let baseURL: String

    public init(apiKey: String, baseURL: String = "https://api.openai.com/v1") {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    public func send(messages: [Message], config: LLMConfig) async throws -> LLMResponse {
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": config.model,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "temperature": config.temperature ?? 0.7,
            "max_tokens": config.maxTokens ?? 4096,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw LLMError.apiError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let content = message?["content"] as? String ?? ""

        let usageDict = json?["usage"] as? [String: Int]
        let usage = usageDict.map {
            TokenUsage(
                promptTokens: $0["prompt_tokens"] ?? 0,
                completionTokens: $0["completion_tokens"] ?? 0,
                totalTokens: $0["total_tokens"] ?? 0
            )
        }

        return LLMResponse(content: content, usage: usage)
    }

    public func stream(messages: [Message], config: LLMConfig) -> AsyncThrowingStream<LLMChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let url = URL(string: "\(baseURL)/chat/completions")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")

                let body: [String: Any] = [
                    "model": config.model,
                    "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
                    "temperature": config.temperature ?? 0.7,
                    "max_tokens": config.maxTokens ?? 4096,
                    "stream": true,
                    "stream_options": ["include_usage": true]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    throw LLMError.apiError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
                }

                for try await line in bytes.lines {
                    guard line.hasPrefix("data: ") else { continue }
                    let jsonStr = String(line.dropFirst(6))
                    if jsonStr == "[DONE]" { break }
                    guard let data = jsonStr.data(using: .utf8),
                          let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

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
                    let finishReason = choices?.first?["finish_reason"] as? String

                    if !content.isEmpty || chunkUsage != nil {
                        continuation.yield(LLMChunk(delta: content, finishReason: finishReason, usage: chunkUsage))
                    }
                }
                continuation.finish()
            }
        }
    }

    public func newConversation(system: String) async throws -> String {
        UUID().uuidString
    }

    public func resume(conversationID: String, message: String) async throws -> String {
        message
    }
}
