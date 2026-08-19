// MeteringTelemetry.swift
// AdventurersCore — Professional Metering, Telemetry & Throughput Specification Models
//
// macOS 15+ · Swift 6 · Sendable-safe

import Foundation
import LLMProviders

// MARK: - Model Pricing & Specification Registry

public struct ModelSpec: Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let family: String
    public let contextLimit: Int
    public let inputCostPerMillion: Double
    public let outputCostPerMillion: Double
    public let reasoningCostPerMillion: Double

    public init(
        name: String,
        family: String,
        contextLimit: Int = 128_000,
        inputCostPerMillion: Double,
        outputCostPerMillion: Double,
        reasoningCostPerMillion: Double? = nil
    ) {
        self.name = name
        self.family = family
        self.contextLimit = contextLimit
        self.inputCostPerMillion = inputCostPerMillion
        self.outputCostPerMillion = outputCostPerMillion
        self.reasoningCostPerMillion = reasoningCostPerMillion ?? outputCostPerMillion
    }

    public func calculateCost(promptTokens: Int, completionTokens: Int, reasoningTokens: Int = 0) -> Double {
        let inputCost = (Double(promptTokens) / 1_000_000.0) * inputCostPerMillion
        let outputNonReasoning = max(0, completionTokens - reasoningTokens)
        let outputCost = (Double(outputNonReasoning) / 1_000_000.0) * outputCostPerMillion
        let reasoningCost = (Double(reasoningTokens) / 1_000_000.0) * reasoningCostPerMillion
        return inputCost + outputCost + reasoningCost
    }
}

public final class ModelPricingRegistry: Sendable {
    public static let shared = ModelPricingRegistry()

    public init() {}

    public func spec(for modelName: String) -> ModelSpec {
        let lower = modelName.lowercased()

        // Anthropic Claude Family
        if lower.contains("claude-3-7-sonnet") || lower.contains("claude-sonnet-4") || lower.contains("claude-3-5-sonnet") {
            return ModelSpec(name: modelName, family: "Claude Sonnet", contextLimit: 200_000, inputCostPerMillion: 3.00, outputCostPerMillion: 15.00, reasoningCostPerMillion: 15.00)
        } else if lower.contains("claude-3-5-haiku") || lower.contains("claude-haiku") {
            return ModelSpec(name: modelName, family: "Claude Haiku", contextLimit: 200_000, inputCostPerMillion: 0.80, outputCostPerMillion: 4.00)
        } else if lower.contains("claude-3-opus") {
            return ModelSpec(name: modelName, family: "Claude Opus", contextLimit: 200_000, inputCostPerMillion: 15.00, outputCostPerMillion: 75.00)
        }

        // OpenAI Family
        if lower.contains("gpt-4o-mini") {
            return ModelSpec(name: modelName, family: "GPT-4o mini", contextLimit: 128_000, inputCostPerMillion: 0.15, outputCostPerMillion: 0.60)
        } else if lower.contains("gpt-4o") || lower.contains("gpt-4-turbo") {
            return ModelSpec(name: modelName, family: "GPT-4o", contextLimit: 128_000, inputCostPerMillion: 2.50, outputCostPerMillion: 10.00)
        } else if lower.contains("o1") || lower.contains("o3-mini") {
            return ModelSpec(name: modelName, family: "OpenAI Reasoning", contextLimit: 200_000, inputCostPerMillion: 1.10, outputCostPerMillion: 4.40, reasoningCostPerMillion: 4.40)
        } else if lower.contains("gpt-5.6-luna") {
            return ModelSpec(name: modelName, family: "Luna Frontier", contextLimit: 128_000, inputCostPerMillion: 0.35, outputCostPerMillion: 1.20)
        }

        // DeepSeek Family
        if lower.contains("deepseek-r1") || lower.contains("reasoner") {
            return ModelSpec(name: modelName, family: "DeepSeek R1", contextLimit: 128_000, inputCostPerMillion: 0.55, outputCostPerMillion: 2.19, reasoningCostPerMillion: 2.19)
        } else if lower.contains("deepseek-v4-flash") || lower.contains("deepseek-chat") || lower.contains("deepseek-v3") {
            return ModelSpec(name: modelName, family: "DeepSeek V3", contextLimit: 128_000, inputCostPerMillion: 0.14, outputCostPerMillion: 0.28)
        } else if lower.contains("deepseek-v4-pro") {
            return ModelSpec(name: modelName, family: "DeepSeek Pro", contextLimit: 128_000, inputCostPerMillion: 0.25, outputCostPerMillion: 0.70)
        }

        // Qwen Family
        if lower.contains("qwen3.8-max") || lower.contains("qwen3.7-max") {
            return ModelSpec(name: modelName, family: "Qwen Max", contextLimit: 128_000, inputCostPerMillion: 0.60, outputCostPerMillion: 2.40)
        } else if lower.contains("qwen3.7-plus") || lower.contains("qwen2.5-coder") || lower.contains("qwen") {
            return ModelSpec(name: modelName, family: "Qwen Plus", contextLimit: 128_000, inputCostPerMillion: 0.20, outputCostPerMillion: 0.60)
        }

        // GLM Family
        if lower.contains("glm-5.3") || lower.contains("glm-5.2") || lower.contains("glm-5.1") || lower.contains("glm-4") {
            return ModelSpec(name: modelName, family: "GLM Reasoning", contextLimit: 128_000, inputCostPerMillion: 1.00, outputCostPerMillion: 2.00)
        }

        // MiniMax Family
        if lower.contains("minimax-m2.7") || lower.contains("minimax-m3") || lower.contains("minimax") {
            return ModelSpec(name: modelName, family: "MiniMax LongContext", contextLimit: 1_000_000, inputCostPerMillion: 0.15, outputCostPerMillion: 0.50)
        }

        // Kimi / Moonshot Family
        if lower.contains("kimi-k3") || lower.contains("kimi-k2.7") || lower.contains("kimi-k2.6") || lower.contains("kimi") {
            return ModelSpec(name: modelName, family: "Kimi Coder", contextLimit: 256_000, inputCostPerMillion: 0.80, outputCostPerMillion: 2.40)
        }

        // OpenCode Mimo Family
        if lower.contains("mimo-v2.5") {
            return ModelSpec(name: modelName, family: "OpenCode Mimo", contextLimit: 128_000, inputCostPerMillion: 0.10, outputCostPerMillion: 0.20)
        }

        // Meta Muse Spark Family
        if lower.contains("muse-spark") || lower.contains("muse") {
            if lower.contains("contributor") {
                return ModelSpec(name: modelName, family: "Meta Muse Spark (Contributor)", contextLimit: 1_000_000, inputCostPerMillion: 0.10, outputCostPerMillion: 0.20)
            } else {
                return ModelSpec(name: modelName, family: "Meta Muse Spark", contextLimit: 1_000_000, inputCostPerMillion: 1.25, outputCostPerMillion: 4.25)
            }
        }

        // Default Generic Cloud / OSS Model
        return ModelSpec(name: modelName, family: "Universal LLM", contextLimit: 128_000, inputCostPerMillion: 0.50, outputCostPerMillion: 1.50)
    }
}

// MARK: - Turn Telemetry Record

public struct TurnMetrics: Identifiable, Sendable, Codable {
    public let id: UUID
    public let turnNumber: Int
    public let timestamp: Date
    public let model: String
    public let provider: String
    public let promptTokens: Int
    public let completionTokens: Int
    public let reasoningTokens: Int
    public let totalTokens: Int
    public let ttftMs: Double
    public let durationSeconds: Double
    public let tps: Double
    public let peakTps: Double
    public let estimatedCostUSD: Double
    public let toolCallsCount: Int
    public let gatesPassedCount: Int

    public init(
        id: UUID = UUID(),
        turnNumber: Int,
        timestamp: Date = Date(),
        model: String,
        provider: String,
        promptTokens: Int,
        completionTokens: Int,
        reasoningTokens: Int = 0,
        totalTokens: Int? = nil,
        ttftMs: Double,
        durationSeconds: Double,
        tps: Double,
        peakTps: Double,
        estimatedCostUSD: Double,
        toolCallsCount: Int = 0,
        gatesPassedCount: Int = 0
    ) {
        self.id = id
        self.turnNumber = turnNumber
        self.timestamp = timestamp
        self.model = model
        self.provider = provider
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.reasoningTokens = reasoningTokens
        self.totalTokens = totalTokens ?? (promptTokens + completionTokens)
        self.ttftMs = ttftMs
        self.durationSeconds = durationSeconds
        self.tps = tps
        self.peakTps = peakTps
        self.estimatedCostUSD = estimatedCostUSD
        self.toolCallsCount = toolCallsCount
        self.gatesPassedCount = gatesPassedCount
    }

    public var formattedTPS: String {
        String(format: "%.1f tok/s", tps)
    }

    public var formattedPeakTPS: String {
        String(format: "%.1f tok/s", peakTps)
    }

    public var formattedTTFT: String {
        if ttftMs >= 1000 {
            return String(format: "%.2fs TTFT", ttftMs / 1000.0)
        }
        return String(format: "%.0fms TTFT", ttftMs)
    }

    public var formattedDuration: String {
        if durationSeconds < 1.0 {
            return String(format: "%.0fms", durationSeconds * 1000.0)
        }
        return String(format: "%.2fs", durationSeconds)
    }

    public var formattedCost: String {
        if estimatedCostUSD < 0.0001 {
            return "<$0.0001"
        } else if estimatedCostUSD < 0.01 {
            return String(format: "$%.4f", estimatedCostUSD)
        }
        return String(format: "$%.3f", estimatedCostUSD)
    }
}

// MARK: - Context Health Status

public enum ContextHealthStatus: Sendable {
    case optimal    // < 50%
    case moderate   // 50% - 70%
    case high       // 70% - 85%
    case critical   // > 85%

    public var title: String {
        switch self {
        case .optimal:  return "Optimal Headroom"
        case .moderate: return "Normal Usage"
        case .high:     return "High Load"
        case .critical: return "Compaction Recommended"
        }
    }
}
