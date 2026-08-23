// AdventurersCore - Cooperative Cascade Client
// Swift-side client for the local tiny-model cascade sidecar (scripts/adventurers_py/cascade_server.py).
// Mirrors LMStudioBridge's probe-then-call pattern: short-timeout health check, throwing call
// methods, and — critically — every caller treats "unreachable" as "fall through to cloud," never
// as a hard failure. The sidecar is a fast-path optimization, not a dependency.

import Foundation
import LLMProviders

// MARK: - Status & Decisions

public enum CascadeServerStatus: Sendable, Equatable {
    case online(model: String)
    case offline(reason: String)
}

public enum CascadeRouteDecision: String, Sendable {
    case simple = "SIMPLE"
    case complex = "COMPLEX"
}

public enum CascadeSafetyDecision: String, Sendable {
    case safe = "SAFE"
    case dangerous = "DANGEROUS"
}

public enum CascadeEscalationDecision: String, Sendable {
    case continueLocally = "CONTINUE"
    case escalate = "ESCALATE"
}

// MARK: - Cooperative Cascade Client

public actor CooperativeCascadeClient {
    public static let shared = CooperativeCascadeClient()
    public static let defaultBaseURL = "http://127.0.0.1:8899"

    private init() {}

    /// Fast (1.5s timeout) reachability probe. Callers should skip the cascade entirely — not
    /// retry, not wait — on `.offline` and go straight to their existing cloud path.
    public func checkStatus(baseURL: String = defaultBaseURL) async -> CascadeServerStatus {
        guard let url = URL(string: "\(baseURL)/health") else {
            return .offline(reason: "Invalid server URL")
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.5

        do {
            let (data, res) = try await URLSession.shared.data(for: req)
            guard let http = res as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return .offline(reason: "Server returned HTTP \((res as? HTTPURLResponse)?.statusCode ?? 0)")
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let model = json["model"] as? String else {
                return .online(model: "unknown")
            }
            return .online(model: model)
        } catch {
            return .offline(reason: error.localizedDescription)
        }
    }

    /// Classifies a request as simple enough to fast-path locally, or complex enough to need cloud.
    public func route(request: String, baseURL: String = defaultBaseURL) async throws -> CascadeRouteDecision {
        let json = try await post(path: "/route", body: ["request": request], baseURL: baseURL)
        return (json["decision"] as? String).flatMap(CascadeRouteDecision.init) ?? .complex
    }

    /// Extracts a tool call from a natural-language request. Returns nil if the cascade couldn't
    /// produce a valid one (caller should fall back to the cloud loop, not treat this as an error).
    public func extractToolCall(request: String, baseURL: String = defaultBaseURL) async throws -> [String: AnyCodable]? {
        let json = try await post(path: "/extract_tool_call", body: ["request": request], baseURL: baseURL)
        if json["error"] != nil { return nil }
        return json.mapValues { AnyCodable($0) }
    }

    /// Safety classification for a shell command. Advisory only — never a substitute for
    /// `DangerousCommandDetector`'s deterministic regex gate, which stays authoritative. An LLM
    /// judgment call was empirically unreliable here (flagged benign single-file `rm` and normal
    /// `git push` as DANGEROUS on one model; fixed with few-shot, but still non-deterministic
    /// without temperature=0 — see eval_cloud_savings.py for the full finding).
    public func safetyCheck(command: String, baseURL: String = defaultBaseURL) async throws -> CascadeSafetyDecision {
        let json = try await post(path: "/safety_check", body: ["command": command], baseURL: baseURL)
        return (json["decision"] as? String).flatMap(CascadeSafetyDecision.init) ?? .dangerous
    }

    /// Within an already-local multi-step task, decides whether the next step should stay local
    /// or escalate to cloud.
    public func escalateCheck(step: String, baseURL: String = defaultBaseURL) async throws -> CascadeEscalationDecision {
        let json = try await post(path: "/escalate_check", body: ["step": step], baseURL: baseURL)
        return (json["decision"] as? String).flatMap(CascadeEscalationDecision.init) ?? .escalate
    }

    // MARK: - Private

    private func post(path: String, body: [String: String], baseURL: String) async throws -> [String: Any] {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw LLMError.networkError(NSError(domain: "CooperativeCascadeClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL: \(baseURL)\(path)"]))
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15.0
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, res) = try await URLSession.shared.data(for: req)
        guard let http = res as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let statusCode = (res as? HTTPURLResponse)?.statusCode ?? 0
            throw LLMError.apiError(statusCode: statusCode)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.decodingError
        }
        return json
    }
}
