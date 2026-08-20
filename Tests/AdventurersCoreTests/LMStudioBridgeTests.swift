// LMStudioBridgeTests.swift
// Adventurers Harness — Unit Tests for Native LM Studio REST API Bridge & On-Device Routing

import Testing
import Foundation
@testable import AdventurersCore
import LLMProviders

@Suite("LM Studio REST API Bridge & Local Model Registry Suite")
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

    @Test("UniversalCloudProvider initializes cleanly with empty API key for local LM Studio inference")
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
