// AdventurersCore - Tool Approval Escalation System
// Task 2.2: Granular Tool Approval Escalation System

import Foundation
import LLMProviders

// MARK: - Tool Approval Policy

/// Granular permission policy governing tool invocation.
public enum ToolApprovalPolicy: String, Sendable, Codable, Equatable, Hashable, CaseIterable {
    /// Always allow execution without prompting.
    case alwaysAllow = "alwaysAllow"
    /// Always deny execution without prompting.
    case alwaysDeny = "alwaysDeny"
    /// Ask for confirmation on every single tool execution.
    case askEveryTime = "askEveryTime"
    /// Ask once per session; subsequent invocations in the session are allowed.
    case askOncePerSession = "askOncePerSession"
}

// MARK: - Tool Approval Decision

/// Outcome of a tool approval evaluation or user response.
public enum ToolApprovalDecision: Sendable, Equatable {
    case approved
    case denied(reason: String)
    case timedOut

    public var isApproved: Bool {
        if case .approved = self { return true }
        return false
    }

    public var isDenied: Bool {
        if case .denied = self { return true }
        return false
    }

    public var isTimedOut: Bool {
        if case .timedOut = self { return true }
        return false
    }

    public var reason: String? {
        if case .denied(let reason) = self { return reason }
        return nil
    }
}

// MARK: - Tool Approval Request

/// Context descriptor for an approval request.
public struct ToolApprovalRequest: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let toolName: String
    public let riskLevel: RiskLevel
    public let command: String
    public let sessionID: String
    public let timestamp: Date
    public let timeoutSeconds: TimeInterval

    public init(
        id: UUID = UUID(),
        toolName: String,
        riskLevel: RiskLevel,
        command: String = "",
        sessionID: String = "default",
        timestamp: Date = Date(),
        timeoutSeconds: TimeInterval = 30.0
    ) {
        self.id = id
        self.toolName = toolName
        self.riskLevel = riskLevel
        self.command = command
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.timeoutSeconds = timeoutSeconds
    }
}

// MARK: - Tool Approval Token

/// Session token certifying tool authorization.
public struct ToolApprovalToken: Sendable, Codable, Equatable, Hashable {
    public let token: String
    public let toolName: String
    public let sessionID: String
    public let grantedAt: Date

    public init(
        token: String = UUID().uuidString,
        toolName: String,
        sessionID: String,
        grantedAt: Date = Date()
    ) {
        self.token = token
        self.toolName = toolName
        self.sessionID = sessionID
        self.grantedAt = grantedAt
    }
}

// MARK: - Tool Approval Manager

/// Actor managing granular tool execution approvals, session tokens, consecutive rejection tracking,
/// and automatic escalation to `.alwaysDeny` after N consecutive rejections.
public actor ToolApprovalManager {
    public private(set) var defaultPolicy: ToolApprovalPolicy
    public private(set) var maxConsecutiveRejections: Int
    public private(set) var defaultTimeoutSeconds: TimeInterval

    private var toolPolicies: [String: ToolApprovalPolicy] = [:]
    private var riskPolicies: [RiskLevel: ToolApprovalPolicy] = [:]
    private var sessionApprovedTools: [String: Set<String>] = [:] // sessionID -> Set<toolName>
    private var sessionTokens: [String: [String: ToolApprovalToken]] = [:] // sessionID -> [toolName: Token]
    private var rejectionCounters: [String: Int] = [:] // toolName -> consecutive rejection count
    private var pendingContinuations: [UUID: CheckedContinuation<ToolApprovalDecision, Never>] = [:]

    public typealias ApprovalHandler = @Sendable (ToolApprovalRequest) async -> ToolApprovalDecision
    private var approvalHandler: ApprovalHandler?

    /// - Parameter approvalHandler: Set synchronously at construction (rather than via the async
    ///   `setApprovalHandler(_:)`) so there is no window after init where a caller could race
    ///   ahead of handler registration and fall through to the raw continuation/timeout path.
    public init(
        defaultPolicy: ToolApprovalPolicy = .askEveryTime,
        maxConsecutiveRejections: Int = 3,
        defaultTimeoutSeconds: TimeInterval = 30.0,
        approvalHandler: ApprovalHandler? = nil
    ) {
        self.defaultPolicy = defaultPolicy
        self.maxConsecutiveRejections = maxConsecutiveRejections
        self.defaultTimeoutSeconds = defaultTimeoutSeconds
        self.approvalHandler = approvalHandler
    }

    // MARK: - Policy Configuration

    public func setDefaultPolicy(_ policy: ToolApprovalPolicy) {
        self.defaultPolicy = policy
    }

    public func setMaxConsecutiveRejections(_ count: Int) {
        self.maxConsecutiveRejections = max(1, count)
    }

    public func setDefaultTimeoutSeconds(_ seconds: TimeInterval) {
        self.defaultTimeoutSeconds = max(0.1, seconds)
    }

    public func setPolicy(_ policy: ToolApprovalPolicy, for toolName: String) {
        toolPolicies[toolName] = policy
    }

    public func removePolicy(for toolName: String) {
        toolPolicies.removeValue(forKey: toolName)
    }

    public func setPolicy(_ policy: ToolApprovalPolicy, for riskLevel: RiskLevel) {
        riskPolicies[riskLevel] = policy
    }

    public func removePolicy(for riskLevel: RiskLevel) {
        riskPolicies.removeValue(forKey: riskLevel)
    }

    public func policy(for toolName: String, riskLevel: RiskLevel = .execute) -> ToolApprovalPolicy {
        if let specific = toolPolicies[toolName] {
            return specific
        }
        if let byRisk = riskPolicies[riskLevel] {
            return byRisk
        }
        return defaultPolicy
    }

    // MARK: - Approval Handler

    public func setApprovalHandler(_ handler: ApprovalHandler?) {
        self.approvalHandler = handler
    }

    // MARK: - Session Token Tracking

    @discardableResult
    public func grantSessionApproval(for toolName: String, sessionID: String, token: String? = nil) -> ToolApprovalToken {
        let tokenObj = ToolApprovalToken(
            token: token ?? UUID().uuidString,
            toolName: toolName,
            sessionID: sessionID,
            grantedAt: Date()
        )
        sessionApprovedTools[sessionID, default: []].insert(toolName)
        sessionTokens[sessionID, default: [:]][toolName] = tokenObj
        return tokenObj
    }

    public func revokeSessionApproval(for toolName: String, sessionID: String) {
        sessionApprovedTools[sessionID]?.remove(toolName)
        sessionTokens[sessionID]?.removeValue(forKey: toolName)
    }

    public func isSessionApproved(for toolName: String, sessionID: String) -> Bool {
        sessionApprovedTools[sessionID]?.contains(toolName) ?? false
    }

    public func sessionToken(for toolName: String, sessionID: String) -> ToolApprovalToken? {
        sessionTokens[sessionID]?[toolName]
    }

    public func clearSession(_ sessionID: String) {
        sessionApprovedTools.removeValue(forKey: sessionID)
        sessionTokens.removeValue(forKey: sessionID)
    }

    public func clearAllSessions() {
        sessionApprovedTools.removeAll()
        sessionTokens.removeAll()
    }

    // MARK: - Rejection Counter & Auto Escalation

    public func rejectionCount(for toolName: String) -> Int {
        rejectionCounters[toolName] ?? 0
    }

    public func resetRejections(for toolName: String) {
        rejectionCounters[toolName] = 0
    }

    public func resetAllRejections() {
        rejectionCounters.removeAll()
    }

    /// Records a rejection for the given tool.
    /// If consecutive rejections reach or exceed `maxConsecutiveRejections`,
    /// automatically escalates tool policy to `.alwaysDeny`.
    /// - Returns: `true` if policy was escalated to `.alwaysDeny`, `false` otherwise.
    @discardableResult
    public func recordRejection(for toolName: String) -> Bool {
        let newCount = (rejectionCounters[toolName] ?? 0) + 1
        rejectionCounters[toolName] = newCount

        if newCount >= maxConsecutiveRejections {
            toolPolicies[toolName] = .alwaysDeny
            return true
        }
        return false
    }

    // MARK: - Request / Response & Timeout Handling

    /// Main evaluation entry point for requesting tool authorization.
    public func evaluateOrRequestApproval(
        toolName: String,
        riskLevel: RiskLevel = .execute,
        command: String = "",
        sessionID: String = "default",
        timeoutSeconds: TimeInterval? = nil
    ) async -> ToolApprovalDecision {
        let currentPolicy = policy(for: toolName, riskLevel: riskLevel)

        switch currentPolicy {
        case .alwaysAllow:
            resetRejections(for: toolName)
            return .approved

        case .alwaysDeny:
            return .denied(reason: "Tool '\(toolName)' is blocked by policy (.alwaysDeny)")

        case .askOncePerSession:
            if isSessionApproved(for: toolName, sessionID: sessionID) {
                resetRejections(for: toolName)
                return .approved
            }
            fallthrough

        case .askEveryTime:
            let timeout = timeoutSeconds ?? defaultTimeoutSeconds
            let request = ToolApprovalRequest(
                toolName: toolName,
                riskLevel: riskLevel,
                command: command,
                sessionID: sessionID,
                timeoutSeconds: timeout
            )

            let decision = await executeApprovalRequest(request)

            switch decision {
            case .approved:
                resetRejections(for: toolName)
                if currentPolicy == .askOncePerSession {
                    grantSessionApproval(for: toolName, sessionID: sessionID)
                }
            case .denied:
                recordRejection(for: toolName)
            case .timedOut:
                recordRejection(for: toolName)
            }

            return decision
        }
    }

    /// Explicitly submits an approval request with timeout race.
    public func requestApproval(_ request: ToolApprovalRequest) async -> ToolApprovalDecision {
        await executeApprovalRequest(request)
    }

    /// Responds to an in-flight approval request.
    public func respond(to requestID: UUID, with decision: ToolApprovalDecision) {
        if let continuation = pendingContinuations.removeValue(forKey: requestID) {
            continuation.resume(returning: decision)
        }
    }

    private func executeApprovalRequest(_ request: ToolApprovalRequest) async -> ToolApprovalDecision {
        if let handler = approvalHandler {
            // Run handler with timeout protection
            return await withTaskGroup(of: ToolApprovalDecision.self) { group in
                group.addTask {
                    await handler(request)
                }
                group.addTask {
                    let nanos = UInt64(max(0.01, request.timeoutSeconds) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanos)
                    return .timedOut
                }

                if let firstResult = await group.next() {
                    group.cancelAll()
                    return firstResult
                }
                return .timedOut
            }
        }

        // No inline handler; suspend with CheckedContinuation until respond(to:with:) or timeout
        return await withCheckedContinuation { continuation in
            pendingContinuations[request.id] = continuation

            Task { [weak self, requestID = request.id, timeout = request.timeoutSeconds] in
                let nanos = UInt64(max(0.01, timeout) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                await self?.handleTimeout(requestID: requestID)
            }
        }
    }

    private func handleTimeout(requestID: UUID) {
        if let continuation = pendingContinuations.removeValue(forKey: requestID) {
            continuation.resume(returning: .timedOut)
        }
    }
}
