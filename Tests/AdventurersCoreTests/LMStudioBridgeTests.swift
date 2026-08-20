// LMStudioBridgeTests.swift
// Adventurers Harness — Unit Tests for Native LM Studio REST API Bridge & Local Inference Manager

import Testing
import Foundation
@testable import AdventurersCore
import LLMProviders

@Suite("LM Studio & Ollama Local Inference Manager Suite")
struct LMStudioBridgeTests {

    @Test("LM Studio Model Info accurately stores model architecture and context metadata")
    func testModelInfoMetadata() {
        let model = LMStudioModelInfo(
            id: "qwen2.5-coder-32b-instruct",
            name: "Qwen 2.5 Coder 32B Instruct",
            isLoaded: true,
            architecture: "qwen2",
            quantization: "Q4_K_M",
            contextLength: 32768,
            sizeBytes: 19850000000
        )

        #expect(model.id == "qwen2.5-coder-32b-instruct")
        #expect(model.isLoaded == true)
        #expect(model.architecture == "qwen2")
        #expect(model.quantization == "Q4_K_M")
        #expect(model.contextLength == 32768)
    }

    @Test("LM Studio Tool and Function Definition encodes properly matching OpenAI Responses schema")
    func testToolDefinitionSchemaEncoding() throws {
        let params: [String: AnyCodable] = [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "location": ["type": "string", "description": "The city and state, e.g. San Francisco, CA"],
                "unit": ["type": "string", "enum": ["celsius", "fahrenheit"]]
            ]),
            "required": AnyCodable(["location", "unit"])
        ]

        let tool = LMStudioTool(
            name: "get_current_weather",
            description: "Get the current weather in a given location",
            parameters: params
        )

        let encoded = try JSONEncoder().encode(tool)
        let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]

        #expect(json?["type"] as? String == "function")
        #expect(json?["name"] as? String == "get_current_weather")
        #expect(json?["description"] as? String == "Get the current weather in a given location")
    }

    @Test("LM Studio Bridge server status probe returns structured offline state when server is unreachable")
    func testOfflineServerProbe() async {
        let bridge = LMStudioBridge.shared
        let status = await bridge.checkServerStatus(baseURL: "http://127.0.0.1:59999")

        if case .offline(let reason) = status {
            #expect(!reason.isEmpty)
        } else {
            Issue.record("Expected offline status for non-existent port")
        }
    }

    @Test("Local Inference Manager distinguishes LM Studio vs Ollama ports and endpoints")
    func testLocalInferenceEngineDefaults() {
        #expect(LocalEngineType.lmstudio.defaultPort == 1234)
        #expect(LocalEngineType.ollama.defaultPort == 11434)
        #expect(LocalEngineType.lmstudio.defaultBaseURL == "http://localhost:1234/v1")
        #expect(LocalEngineType.ollama.defaultBaseURL == "http://localhost:11434/v1")
    }

    @Test("Local Inference Manager probes offline ports safely without exceptions")
    func testLocalInferenceProbes() async {
        let manager = LocalInferenceManager.shared
        let lmStatus = await manager.probeLMStudio(baseURL: "http://127.0.0.1:59998")
        let ollamaStatus = await manager.probeOllama(baseURL: "http://127.0.0.1:59997")

        #expect(lmStatus.isOnline == false)
        #expect(ollamaStatus.isOnline == false)
    }

    @Test("UniversalCloudProvider initializes cleanly with empty API key for local inference")
    func testLocalLMStudioProviderInit() {
        let provider = UniversalCloudProvider(
            name: "LM Studio",
            apiKey: "",
            baseURL: "http://localhost:1234/v1",
            isAnthropicNative: false
        )

        #expect(provider.name == "LM Studio")
        #expect(provider.baseURL == "http://localhost:1234/v1")
        #expect(provider.supportsConversations == true)
    }
}
