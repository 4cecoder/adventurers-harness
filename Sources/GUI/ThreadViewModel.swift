// ThreadViewModel.swift
// Adventurers Harness — Observable State Manager for Threads, Tool Loops, and Session Persistence

import SwiftUI
import AdventurersCore
import LLMProviders
import Tools

/// The observable state for the entire thread view.
/// Manages messages, gate progress, streaming state, pause/queue controls, and input.
@MainActor
public final class ThreadViewModel: ObservableObject {
    @Published public var messages: [ThreadMessage] = []
    @Published var gateState = GatePipelineState()
    @Published public var inputText: String = ""
    @Published public var selectedModel: String = "gpt-4o"
    @Published public var isGenerating: Bool = false
    @Published public var isPaused: Bool = false
    @Published public var queuedPrompts: [QueuedPrompt] = []
    @Published public var isLoadingSkeleton: Bool = true
    @Published public var availableModels: [String] = [
        "gpt-4o",
        "gpt-4o-mini",
        "claude-sonnet-4-20250514",
        "claude-3-5-haiku-20241022",
    ]

    /// The most recent streaming message ID, used for auto-scroll.
    @Published public var lastStreamingMessageID: String?
    @Published public var workingDirectory: String = WorkspaceConfig.defaultWorkspacePath
    public var workingDirectoryName: String { (workingDirectory as NSString).lastPathComponent }
    public var threadID: UUID?
    @Published public var activeContract: LongHorizonTaskContract?
    public var onMessagesChanged: (([ThreadMessage]) -> Void)?
    public let meteringState = ThreadMeteringState()
    public var activeGenerationTask: Task<Void, Never>? = nil

    /// Drives the permission sheet in `ThreadView`. Non-nil while a tool call is awaiting the
    /// user's Allow/Deny decision.
    @Published var pendingPermissionRequest: PermissionRequest?
    private var pendingPermissionContinuation: CheckedContinuation<PermissionDecision, Never>?

    public init(threadID: UUID? = nil, workingDirectory: String? = nil) {
        self.threadID = threadID
        if let dir = workingDirectory, !dir.isEmpty && dir != "/" {
            self.workingDirectory = dir
        } else {
            self.workingDirectory = WorkspaceConfig.defaultWorkspacePath
        }
        if let id = threadID {
            let loaded = ThreadStore.shared.loadMessages(for: id)
            if !loaded.isEmpty {
                let consolidated = ThreadMessageConsolidator.consolidate(loaded)
                self.messages = consolidated
                self.isLoadingSkeleton = false
                meteringState.recalculateContext(messages: consolidated)
            } else {
                loadPlaceholderMessages()
                meteringState.recalculateContext(messages: self.messages)
            }
        } else {
            loadPlaceholderMessages()
            meteringState.recalculateContext(messages: self.messages)
        }
    }

    /// Checks old messages on opening thread and compounds multi-turn tool call runs into clean single cards.
    @discardableResult
    public func consolidateOldMessagesIfNeeded() -> Bool {
        let originalCount = messages.count
        let consolidated = ThreadMessageConsolidator.consolidate(messages)
        if consolidated.count != originalCount {
            self.messages = consolidated
            meteringState.recalculateContext(messages: consolidated)
            onMessagesChanged?(consolidated)
            return true
        }
        return false
    }

    // MARK: - Execution Controls (Pause, Resume, Stop, Queue)

    public func pauseRun(terminalManager: TerminalManager? = nil) {
        guard isGenerating, !isPaused else { return }
        isPaused = true
        terminalManager?.logCommand("[Execution Paused] Thread suspended. Click Resume or press ⌥Space to continue.")
    }

    public func resumeRun(terminalManager: TerminalManager? = nil) {
        guard isGenerating, isPaused else { return }
        isPaused = false
        terminalManager?.logCommand("[Execution Resumed] Continuing agent loop.")
    }

    public func togglePause(terminalManager: TerminalManager? = nil) {
        if isPaused {
            resumeRun(terminalManager: terminalManager)
        } else {
            pauseRun(terminalManager: terminalManager)
        }
    }

    public func stopRun(terminalManager: TerminalManager? = nil) {
        guard isGenerating || !queuedPrompts.isEmpty else { return }
        activeGenerationTask?.cancel()
        activeGenerationTask = nil
        isGenerating = false
        isPaused = false
        if let msgID = lastStreamingMessageID {
            finishStreaming(messageID: msgID)
        }
        ActiveProcessRegistry.shared.killAllProcesses()
        terminalManager?.logError("[Execution Stopped] Agent run aborted by user. All active subprocesses (find, bash, tools) terminated.")
    }

    public func queuePrompt(_ text: String, terminalManager: TerminalManager? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        queuedPrompts.append(QueuedPrompt(text: trimmed))
        inputText = ""
        terminalManager?.logCommand("[Prompt Queued (#\(queuedPrompts.count))] \"\(trimmed.prefix(60))...\"")
    }

    public func removeQueuedPrompt(id: String) {
        queuedPrompts.removeAll(where: { $0.id == id })
    }

    public func clearQueuedPrompts() {
        queuedPrompts.removeAll()
    }

    public var hasCheckpoints: Bool = false

    /// Roll back the workspace to the most recent pre-execution snapshot
    @discardableResult
    public func rollbackLatestCheckpoint(terminalManager: TerminalManager? = nil) async -> Bool {
        guard let threadUUID = self.threadID else { return false }
        let list = await SessionCheckpointEngine.shared.getCheckpoints(for: threadUUID)
        guard let latest = list.last else { return false }
        do {
            let restored = try await SessionCheckpointEngine.shared.rollback(
                sessionID: threadUUID,
                checkpointID: latest.id,
                workspacePath: self.workingDirectory
            )
            terminalManager?.logCommand("[Rollback Executed] Reverted \(restored.count) file(s) to checkpoint (Turn #\(latest.turnNumber)).")
            return true
        } catch {
            terminalManager?.logError("[Rollback Failed] \(error.localizedDescription)")
            return false
        }
    }

    public func checkPauseState() async {
        while isPaused && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(120))
        }
    }

    // MARK: - Public API

    /// Append a new message to the thread.
    public func appendMessage(_ message: ThreadMessage) {
        messages.append(message)
        if message.isStreaming {
            lastStreamingMessageID = message.id
        }
        isLoadingSkeleton = false
        meteringState.recalculateContext(messages: messages)
        onMessagesChanged?(messages)
    }

    /// Update an existing message by ID (used during streaming).
    public func updateMessage(id: String, content: String, toolCalls: [ThreadToolCall]? = nil) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        let old = messages[index]
        messages[index] = ThreadMessage(
            id: old.id,
            role: old.role,
            content: content,
            timestamp: old.timestamp,
            toolCalls: toolCalls ?? old.toolCalls,
            toolResults: old.toolResults,
            isStreaming: old.isStreaming,
            thinkingContent: old.thinkingContent
        )
    }

    /// Update message with reasoning content (DeepSeek R1 / GLM stream).
    public func updateMessageWithReasoning(id: String, content: String, reasoning: String?) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        let old = messages[index]
        messages[index] = ThreadMessage(
            id: old.id,
            role: old.role,
            content: content,
            timestamp: old.timestamp,
            toolCalls: old.toolCalls,
            toolResults: old.toolResults,
            isStreaming: old.isStreaming,
            thinkingContent: reasoning
        )
    }

    /// Mark a message as no longer streaming.
    public func finishStreaming(messageID: String) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        let old = messages[index]
        messages[index] = ThreadMessage(
            id: old.id,
            role: old.role,
            content: old.content,
            timestamp: old.timestamp,
            toolCalls: old.toolCalls,
            toolResults: old.toolResults,
            isStreaming: false,
            thinkingContent: old.thinkingContent
        )
        if lastStreamingMessageID == messageID {
            lastStreamingMessageID = nil
        }
        onMessagesChanged?(messages)
    }

    /// Update gate progress by name.
    public func updateGate(name: String, passed: Bool) {
        if let id = GateIdentifier.allCases.first(where: { $0.rawValue == name }) {
            if passed {
                let result = GateResult(passed: true, gateName: name, output: "OK")
                gateState.passGate(id, result: result, elapsed: 0)
            } else {
                let result = GateResult(passed: false, gateName: name, error: "Failed")
                gateState.failGate(id, result: result, errorCount: 1, elapsed: 0)
            }
        }
    }

    /// Reset all gates to pending.
    public func resetGates() {
        gateState = GatePipelineState()
    }

    /// Send the current input as a user message and trigger live multi-turn cloud execution with tool execution.
    public func sendMessage(
        settings: SettingsModel? = nil,
        terminalManager: TerminalManager? = nil,
        diffState: DiffViewerState? = nil
    ) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if isGenerating {
            queuePrompt(text, terminalManager: terminalManager)
            return
        }

        let userMessage = ThreadMessage(role: .user, content: text)
        appendMessage(userMessage)
        inputText = ""
        isGenerating = true
        isPaused = false
        resetGates()

        // Handle Meta-Harness Mode (Sub-Agent External CLI dispatch)
        if let s = settings, s.executionMode == .metaHarness {
            let selectedHarness = s.selectedMetaHarness
            let profile = s.profile(for: selectedHarness)

            terminalManager?.logCommand("[Meta Harness Dispatch] Target: \(selectedHarness.rawValue) | Binary: \(profile.binaryPath)")

            self.activeGenerationTask = Task {
                let agentMessageID = UUID().uuidString
                let placeholder = ThreadMessage(
                    id: agentMessageID,
                    role: .agent,
                    content: "",
                    isStreaming: true
                )
                self.appendMessage(placeholder)

                self.meteringState.startTurn(
                    model: profile.binaryPath,
                    provider: selectedHarness.rawValue,
                    estimatedPromptTokens: max(10, Int(ceil(Double(text.count) / 3.6)))
                )

                var accumulatedOutput = ""
                let workspace = self.workingDirectory

                do {
                    await self.checkPauseState()
                    guard !Task.isCancelled else {
                        self.finishStreaming(messageID: agentMessageID)
                        self.isGenerating = false
                        self.isPaused = false
                        return
                    }

                    let exitCode = try await MetaHarnessRunner.shared.executeHarness(
                        profile: profile,
                        prompt: text,
                        workspacePath: workspace
                    ) { [weak self] chunk in
                        Task { @MainActor in
                            accumulatedOutput += chunk
                            self?.updateMessage(id: agentMessageID, content: accumulatedOutput)
                            self?.meteringState.recordStreamChunk(deltaText: chunk)
                        }
                    }

                    if accumulatedOutput.isEmpty {
                        accumulatedOutput = "Sub-harness process '\(profile.binaryPath)' completed with exit code \(exitCode)."
                        self.updateMessage(id: agentMessageID, content: accumulatedOutput)
                    }

                    self.finishStreaming(messageID: agentMessageID)
                    await self.certifyOutput(content: accumulatedOutput, prompt: text, terminalManager: terminalManager)
                    self.meteringState.finishTurn(toolCallsCount: 0, gatesPassedCount: 6)
                    self.isGenerating = false
                    self.isPaused = false
                    self.activeGenerationTask = nil
                    terminalManager?.logOutput("Process exited with code \(exitCode)")

                    // Process next queued prompt if available
                    self.processNextQueuedPrompt(settings: settings, terminalManager: terminalManager, diffState: diffState)
                } catch {
                    let errStr = "Error executing Meta Harness '\(profile.binaryPath)': \(error.localizedDescription)\nEnsure the binary is installed or update the path in Settings → Meta Harness CLIs."
                    self.updateMessage(id: agentMessageID, content: errStr)
                    self.finishStreaming(messageID: agentMessageID)
                    self.isGenerating = false
                    self.isPaused = false
                    self.activeGenerationTask = nil
                    terminalManager?.logError(errStr)
                }
            }
            return
        }

        // Direct Coding Plan Mode (Cloud LLM API Streaming)
        let providerType = settings?.activeProvider ?? .opencode
        let apiKey = settings?.apiKey ?? ""
        let baseURL = settings?.baseURL.isEmpty == false ? settings!.baseURL : providerType.defaultBaseURL

        guard !apiKey.isEmpty else {
            let errorMessage = ThreadMessage(
                role: .system,
                content: "Error: No API key configured for \(providerType.rawValue). Please add your API key in Settings → Coding Plan Keys."
            )
            appendMessage(errorMessage)
            isGenerating = false
            return
        }
        let model = settings?.selectedModel ?? selectedModel

        self.activeGenerationTask = Task {
            let provider = UniversalCloudProvider(
                name: providerType.rawValue,
                apiKey: apiKey,
                baseURL: baseURL,
                isAnthropicNative: providerType == .anthropic
            )

            let config = LLMConfig(
                provider: providerType.rawValue,
                model: model,
                temperature: settings?.temperature ?? 0.2,
                maxTokens: settings?.maxTokens ?? 4096,
                baseURL: baseURL,
                apiKey: apiKey
            )

            // ⚡ Cactus Needle 2 On-Device Fast-Path Preflight (<15ms, 14MB)
            let needleDecision = NeedleProcessor.shared.process(
                prompt: text,
                workspaceFiles: [],
                knownTools: ["run_command", "view_file", "grep_search", "list_dir"]
            )

            if case .localFastExecute(let toolName, let args) = needleDecision.mode, needleDecision.confidence >= NeedleProcessor.shared.confidenceThreshold {
                terminalManager?.logCommand("[⚡ Cactus Needle 2 Fast-Path] Routed to '\(toolName)' in \(String(format: "%.1f", needleDecision.latencyMs))ms (Confidence: \(Int(needleDecision.confidence * 100))%, Est. Savings: \(needleDecision.tokenSavingsEstimated) tokens)")

                let agentMsgID = UUID().uuidString
                let initialMsg = ThreadMessage(
                    id: agentMsgID,
                    role: .agent,
                    content: "⚡ *Executing instant local tool via Cactus Needle 2 on-device engine (\(String(format: "%.1f", needleDecision.latencyMs))ms latency)...*",
                    toolCalls: [
                        ThreadToolCall(id: "needle-call-1", name: toolName, arguments: args.description, status: .running)
                    ],
                    isStreaming: true
                )
                self.appendMessage(initialMsg)

                let anyArgs = args.mapValues { AnyCodable($0) }
                let toolExecResult = await self.executeNativeTool(name: toolName, arguments: anyArgs)

                let cleanOutput = toolName == "run_command" || toolName == "bash" 
                    ? NeedleOutputCompactor.compactBuildLog(toolExecResult.output)
                    : toolExecResult.output

                let isErr = toolExecResult.error != nil && !toolExecResult.error!.isEmpty
                let completedMsg = ThreadMessage(
                    id: agentMsgID,
                    role: .agent,
                    content: isErr ? "Tool execution encountered an issue." : "⚡ Executed via Cactus Needle 2 on-device intelligence.",
                    toolCalls: [
                        ThreadToolCall(id: "needle-call-1", name: toolName, arguments: args.description, status: isErr ? .failed(error: toolExecResult.error ?? "Failed") : .succeeded(output: cleanOutput))
                    ],
                    toolResults: [
                        ThreadToolResult(id: "needle-res-1", toolCallID: "needle-call-1", output: isErr ? (toolExecResult.error ?? "") : cleanOutput, isError: isErr)
                    ],
                    isStreaming: false
                )
                if let idx = self.messages.firstIndex(where: { $0.id == agentMsgID }) {
                    self.messages[idx] = completedMsg
                }
                self.isGenerating = false
                self.isLoadingSkeleton = false
                return
            }

            let judgerDecision = TaskJudgerEngine.shared.evaluate(prompt: text)
            var maxTurns = judgerDecision.recommendedTurnBudget

            if judgerDecision.shouldInitializeTaskContract, let threadUUID = self.threadID {
                self.activeContract = LongHorizonTaskContract(
                    id: threadUUID,
                    goal: text,
                    currentPhase: .planning,
                    turnBudget: judgerDecision.recommendedTurnBudget
                )
            } else {
                self.activeContract = nil
            }

            let threadWorkspace = self.workingDirectory
            let systemPrompt = """
            You are Adventurers Harness, an autonomous agentic pair programmer with direct access to the local codebase through native tools.
            Your thread is rooted in the working directory: \(threadWorkspace).

            PIPELINE OPTIMIZATION & TASK GUIDANCE:
            • Mode: \(judgerDecision.tier.rawValue)
            • \(judgerDecision.systemGuidanceSnippet)

            WORKSPACE SCOPE & CONFINEMENT RULES:
            1. SCOPE RETENTION: All relative file paths and tool calls (view_file, write_file, edit_file, list_dir, grep_search, bash) MUST resolve relative to and operate strictly inside '\(threadWorkspace)' by default.
            2. DIRECTORY BOUNDARY INTEGRITY: Do NOT wander outside this directory tree (e.g. into parent directories '..', sibling repositories, or system paths) unless the user's instructions explicitly and unambiguously command accessing an external path.
            3. Keep all scratch files, edits, test commands, and builds scoped to '\(threadWorkspace)'.

            COMPOUND EXECUTION & RIGOROUS HARNESS DISCIPLINE:
            • SHORT-HORIZON COMPOUNDING: Tackle work in tight, verified, atomic steps. Short focused turns compound into deep, verified context without hallucination.
            • HONEST CAPABILITY BOUNDARIES: Never pretend a tool, command, or build succeeded if it didn't. Report exact compiler, test, and runtime truth.
            • ALIGNMENT & CLARIFICATION: If a request is ambiguous, dangerous, or underspecified, grill the user on exact constraints and tradeoffs before writing code.
            • RIGID ARCHITECTURAL BEAUTY: Produce clean, modular, production-grade code with zero sloppy hacks, strict type-safety, and deterministic test verification.

            LONG-HORIZON AGENTIC EXECUTION PRINCIPLES (OpenCode & Hermes):
            • STEP DISCIPLINE: For multi-step tasks, outline a concise step plan, execute one atomic change at a time, and verify with tests or compiler checks.
            • PREFLIGHT INSPECTION: Always read existing files (`view_file`) or search symbols (`grep_search`) before proposing edits. Never make blind replacements.
            • SELF-CORRECTION & RECOVERY: When a build, test, or tool call fails, analyze the exact error output, isolate the cause, and fix it directly. Do not repeat failed identical calls.
            • CONCISE HIGH-VELOCITY ACTION: Focus on tool invocations and solutions. Avoid unnecessary preamble.

            You have the following tools available:
            1. `view_file`: Read contents of a file with line numbers (path, start_line, end_line)
            2. `write_file`: Create or completely overwrite a file (path, content)
            3. `edit_file`: Replace an exact unique target substring with new replacement content (path, target, replacement)
            4. `list_dir`: List directory files and folders (path, recursive)
            5. `grep_search`: Search for exact string patterns or regex across files (query, path, file_pattern)
            6. `bash`: Run shell commands in the project directory (command)
            7. `glob`: Find files matching a glob pattern (pattern, path)

            To invoke a tool, output XML format:
            <tool_call>
            <tool_name>tool_name</tool_name>
            <arguments>
            {
              "argument_name": "value"
            }
            </arguments>
            </tool_call>

            Or Markdown code block format:
            ```tool_call
            {
              "name": "tool_name",
              "arguments": { ... }
            }
            ```

            When you invoke a tool, the harness will execute it locally and return the output in the next turn.
            Always inspect files before modifying them, run `swift test` or `swift build` to verify your changes, and make sure your solution satisfies all deterministic certification gates.
            """

            var llmMessages: [Message] = [
                Message(role: .system, content: systemPrompt)
            ]
            for msg in self.messages {
                let role: Message.Role = msg.role == .user ? .user : .assistant
                llmMessages.append(Message(role: role, content: msg.content))
            }

            let compactor = ContextCompactor()
            var finalContent = ""
            var totalToolsExecuted = 0

            let totalPromptChars = llmMessages.map(\.content).joined().count
            let estimatedPromptTokens = max(10, Int(ceil(Double(totalPromptChars) / 3.6)))
            self.meteringState.startTurn(
                model: model,
                provider: providerType.rawValue,
                estimatedPromptTokens: estimatedPromptTokens
            )

            terminalManager?.logCommand("[Task Judger] Tier: \(judgerDecision.tier.rawValue) | Budget: \(judgerDecision.recommendedTurnBudget) turns | Est. Savings: ~\(Int(judgerDecision.estimatedTokenSavingsPercent))%")
            terminalManager?.logCommand("[Agent Dispatch] Provider: \(providerType.rawValue) | Model: \(model)")

            let agentMessageID = UUID().uuidString
            let placeholder = ThreadMessage(
                id: agentMessageID,
                role: .agent,
                content: "",
                isStreaming: true
            )
            self.appendMessage(placeholder)

            var compoundedToolCalls: [ThreadToolCall] = []
            var compoundedToolResults: [ThreadToolResult] = []
            var compoundedReasoning = ""

            var currentTurn = 0
            while maxTurns > 0 && !Task.isCancelled {
                await self.checkPauseState()
                guard !Task.isCancelled else { break }

                maxTurns -= 1
                currentTurn += 1
                var accumulatedContent = ""
                var accumulatedReasoning = ""

                do {
                    let activeMessages = await compactor.compact(messages: llmMessages, contextLimit: 128_000)
                    let stream = provider.stream(messages: activeMessages, config: config)
                    for try await chunk in stream {
                        await self.checkPauseState()
                        guard !Task.isCancelled else { break }

                        if let reasoning = chunk.reasoningDelta, !reasoning.isEmpty {
                            accumulatedReasoning += reasoning
                            compoundedReasoning += reasoning
                        }
                        if !chunk.delta.isEmpty {
                            accumulatedContent += chunk.delta
                        }

                        self.meteringState.recordStreamChunk(
                            deltaText: chunk.delta,
                            reasoningDelta: chunk.reasoningDelta,
                            exactUsage: chunk.usage
                        )

                        let cleanLive = self.toolParser.cleanMessageContent(from: accumulatedContent)
                        if let idx = self.messages.firstIndex(where: { $0.id == agentMessageID }) {
                            let old = self.messages[idx]
                            self.messages[idx] = ThreadMessage(
                                id: old.id,
                                role: old.role,
                                content: cleanLive,
                                timestamp: old.timestamp,
                                toolCalls: compoundedToolCalls,
                                toolResults: compoundedToolResults,
                                isStreaming: true,
                                thinkingContent: compoundedReasoning.isEmpty ? nil : compoundedReasoning
                            )
                        }
                    }

                    if Task.isCancelled { break }

                    // Check for tool calls
                    let toolInvocations = self.extractToolCalls(from: accumulatedContent)
                    if toolInvocations.isEmpty {
                        // Final synthesis without further tool calls
                        let cleaned = self.toolParser.cleanMessageContent(from: accumulatedContent)
                        self.finishStreaming(messageID: agentMessageID)
                        if let idx = self.messages.firstIndex(where: { $0.id == agentMessageID }) {
                            let old = self.messages[idx]
                            self.messages[idx] = ThreadMessage(
                                id: old.id,
                                role: old.role,
                                content: cleaned.isEmpty ? (compoundedToolCalls.isEmpty ? "" : "Executed \(compoundedToolCalls.count) tool\(compoundedToolCalls.count == 1 ? "" : "s").") : cleaned,
                                timestamp: old.timestamp,
                                toolCalls: compoundedToolCalls,
                                toolResults: compoundedToolResults,
                                isStreaming: false,
                                thinkingContent: compoundedReasoning.isEmpty ? nil : compoundedReasoning
                            )
                            self.onMessagesChanged?(self.messages)
                        }
                        finalContent = cleaned
                        break // Done, multi-turn sequence finished
                    }

                    totalToolsExecuted += toolInvocations.count

                    // Auto-Snapshot for Long-Horizon Rollback Protection
                    if let threadUUID = self.threadID {
                        var targetFiles: [String] = []
                        for inv in toolInvocations {
                            if let fp = inv.arguments["TargetFile"]?.stringValue
                                ?? inv.arguments["filePath"]?.stringValue
                                ?? inv.arguments["path"]?.stringValue {
                                targetFiles.append(fp)
                            }
                        }
                        _ = await SessionCheckpointEngine.shared.createCheckpoint(
                            sessionID: threadUUID,
                            turnNumber: totalToolsExecuted,
                            summary: "Pre-execution snapshot before: \(toolInvocations.map(\.name).joined(separator: ", "))",
                            workspacePath: self.workingDirectory,
                            targetFiles: targetFiles
                        )
                        self.hasCheckpoints = true
                    }

                    // Execute tools and compound into unified message
                    var executedToolResults: [String] = []

                    for inv in toolInvocations {
                        await self.checkPauseState()
                        guard !Task.isCancelled else { break }

                        terminalManager?.logCommand("[Tool Execution] \(inv.name) -> \(inv.argumentsSummary)")
                        let tcID = UUID().uuidString
                        let trID = UUID().uuidString

                        let result = await self.executeNativeTool(name: inv.name, arguments: inv.arguments)
                        let outputStr = result.error != nil ? "Error: \(result.error!)" : result.output

                        let toolStatus: ThreadToolCall.ToolCallStatus = (result.error != nil)
                            ? .failed(error: result.error!)
                            : .succeeded(output: outputStr)
                        let toolCall = ThreadToolCall(id: tcID, name: inv.name, arguments: inv.argumentsSummary, status: toolStatus)
                        compoundedToolCalls.append(toolCall)

                        let toolResult = ThreadToolResult(id: trID, toolCallID: tcID, output: outputStr, isError: result.error != nil)
                        compoundedToolResults.append(toolResult)

                        executedToolResults.append("Tool '\(inv.name)' result:\n\(outputStr)")
                        if let err = result.error {
                            terminalManager?.logError("[Tool Error] \(err)")
                        } else {
                            terminalManager?.logOutput("[Tool Output]\n\(outputStr.prefix(300))")
                        }
                    }

                    // Update unified message with compounded tool calls
                    let cleanedInterim = self.toolParser.cleanMessageContent(from: accumulatedContent)
                    if let idx = self.messages.firstIndex(where: { $0.id == agentMessageID }) {
                        let old = self.messages[idx]
                        self.messages[idx] = ThreadMessage(
                            id: old.id,
                            role: old.role,
                            content: cleanedInterim,
                            timestamp: old.timestamp,
                            toolCalls: compoundedToolCalls,
                            toolResults: compoundedToolResults,
                            isStreaming: true,
                            thinkingContent: compoundedReasoning.isEmpty ? nil : compoundedReasoning
                        )
                        self.onMessagesChanged?(self.messages)
                    }

                    // Check for dynamic upgrade from Short-Horizon to Long-Horizon based on decisions
                    var touchedFiles: Set<String> = []
                    for inv in toolInvocations {
                        if let fp = inv.arguments["TargetFile"]?.stringValue
                            ?? inv.arguments["filePath"]?.stringValue
                            ?? inv.arguments["path"]?.stringValue {
                            touchedFiles.insert(fp)
                        }
                    }

                    let hasError = executedToolResults.contains { $0.contains("Error:") }
                    if let upgrade = TaskJudgerEngine.shared.upgradeIfNecessary(
                        currentTier: judgerDecision.tier,
                        turnIndex: currentTurn,
                        modifiedFilesCount: touchedFiles.count,
                        hasErrorOrRetry: hasError,
                        prompt: text
                    ) {
                        maxTurns = upgrade.recommendedTurnBudget
                        if self.activeContract == nil, let threadUUID = self.threadID {
                            self.activeContract = LongHorizonTaskContract(
                                id: threadUUID,
                                goal: text,
                                currentPhase: .execution,
                                turnBudget: maxTurns
                            )
                        }
                        terminalManager?.logCommand("[Task Judger] ⚡ Upgraded to \(upgrade.tier.rawValue): \(upgrade.reason)")
                    }

                    // Add tool results to LLM messages for next turn (budgeted for long horizons)
                    let budgetedResults = executedToolResults.map { ThreadToolExecutor.budgetOutput($0) }
                    llmMessages.append(Message(role: .assistant, content: accumulatedContent))
                    llmMessages.append(Message(role: .user, content: budgetedResults.joined(separator: "\n\n")))

                } catch {
                    let fallbackContent = accumulatedContent.isEmpty ? "⚠️ Notice: \(error.localizedDescription)" : accumulatedContent
                    self.updateMessage(id: agentMessageID, content: fallbackContent)
                    self.finishStreaming(messageID: agentMessageID)
                    terminalManager?.logError("[Notice] \(error.localizedDescription)")
                    finalContent = fallbackContent
                    break
                }
            }

            self.finishStreaming(messageID: agentMessageID)

            if !Task.isCancelled {
                // Run Deterministic Certification Gates Pipeline
                let passedGatesCount = await self.certifyOutput(
                    content: finalContent,
                    prompt: text,
                    terminalManager: terminalManager
                )

                // Finalize Turn Telemetry & Context Window Recalculation
                self.meteringState.finishTurn(
                    toolCallsCount: totalToolsExecuted,
                    gatesPassedCount: passedGatesCount
                )
                self.meteringState.recalculateContext(messages: self.messages)
            }

            self.isGenerating = false
            self.isPaused = false
            self.activeGenerationTask = nil

            // Process next queued prompt if any
            if !Task.isCancelled {
                self.processNextQueuedPrompt(settings: settings, terminalManager: terminalManager, diffState: diffState)
            }
        }
    }

    public func processNextQueuedPrompt(
        settings: SettingsModel? = nil,
        terminalManager: TerminalManager? = nil,
        diffState: DiffViewerState? = nil
    ) {
        guard !isGenerating, !queuedPrompts.isEmpty else { return }
        let next = queuedPrompts.removeFirst()
        inputText = next.text
        sendMessage(settings: settings, terminalManager: terminalManager, diffState: diffState)
    }

    private let toolExecutor = ThreadToolExecutor()
    private let toolParser = ThreadToolCallParser()
    private let gateCertifier = ThreadGateCertifier()

    /// Gatekeeps every native tool call — including the Cactus Needle 2 fast-path — behind a
    /// user-facing approval prompt. Nothing should call `toolExecutor.execute` directly; route
    /// through `executeNativeTool` instead so approval can't be bypassed.
    ///
    /// The handler is passed in at construction (rather than via the async `setApprovalHandler`)
    /// so there's no window where a tool call could race ahead of registration and silently fall
    /// through to the raw continuation/timeout path with no dialog ever shown.
    private lazy var toolApprovalManager = ToolApprovalManager(
        defaultTimeoutSeconds: 180,
        approvalHandler: { [weak self] request in
            guard let self else { return .denied(reason: "No active thread to confirm with") }
            return await self.presentApprovalDialog(for: request)
        }
    )

    private func extractToolCalls(from text: String) -> [ThreadToolCallParser.ToolInvocation] {
        toolParser.extractToolCalls(from: text)
    }

    private func executeNativeTool(name: String, arguments: [String: AnyCodable]) async -> ToolResult {
        let commandArg = arguments["command"]?.stringValue
            ?? arguments["path"]?.stringValue
            ?? arguments.description
        let risk = riskLevel(for: name, commandArg: commandArg)

        let decision = await toolApprovalManager.evaluateOrRequestApproval(
            toolName: name,
            riskLevel: risk,
            command: commandArg,
            sessionID: threadID?.uuidString ?? "default"
        )
        guard decision.isApproved else {
            return ToolResult(output: "", error: "Tool '\(name)' was not approved: \(decision.reason ?? "denied by user")")
        }

        return await toolExecutor.execute(name: name, arguments: arguments, workingDirectory: self.workingDirectory)
    }

    private func riskLevel(for toolName: String, commandArg: String) -> RiskLevel {
        switch toolName {
        case "bash", "run_command", "shell":
            return DangerousCommandDetector.shared.detectDangerousCommand(commandArg)?.risk ?? .execute
        case "write_file", "create_file", "edit_file", "patch_file":
            return .write
        default:
            return .readOnly
        }
    }

    /// Shows the permission sheet and suspends until the user responds. Runs on the main actor
    /// since it drives `@Published` UI state.
    @MainActor
    private func presentApprovalDialog(for request: ToolApprovalRequest) async -> ToolApprovalDecision {
        let permissionRequest = PermissionRequest(
            toolName: request.toolName,
            riskLevel: request.riskLevel,
            command: request.command,
            agentID: request.sessionID,
            timestamp: request.timestamp
        )

        let decision: PermissionDecision = await withCheckedContinuation { continuation in
            self.pendingPermissionContinuation = continuation
            self.pendingPermissionRequest = permissionRequest
        }
        self.pendingPermissionRequest = nil

        switch decision {
        case .allowOnce:
            return .approved
        case .allowForSession:
            await toolApprovalManager.setPolicy(.askOncePerSession, for: request.toolName)
            await toolApprovalManager.grantSessionApproval(for: request.toolName, sessionID: request.sessionID)
            return .approved
        case .deny:
            return .denied(reason: "User denied the tool request")
        }
    }

    /// Called by `ThreadView` when the user taps Allow/Deny on `pendingPermissionRequest`.
    func resolvePendingPermission(_ decision: PermissionDecision) {
        pendingPermissionContinuation?.resume(returning: decision)
        pendingPermissionContinuation = nil
    }

    @discardableResult
    private func certifyOutput(content: String, prompt: String, terminalManager: TerminalManager?) async -> Int {
        terminalManager?.logCommand("[Gates Engine] Evaluating 6-gate deterministic certification pipeline...")

        let result = await gateCertifier.certify(content: content, prompt: prompt)
        var passedCount = 0

        // Update gate states
        for (gate, passed) in result.gateResults {
            if let id = GateIdentifier.allCases.first(where: { $0.rawValue == gate }) {
                if passed {
                    passedCount += 1
                    gateState.passGate(id, result: GateResult(passed: true, gateName: gate, output: "OK"), elapsed: 0)
                    terminalManager?.logOutput("  ✔ [Gate: \(gate)] Passed")
                } else if let error = result.errors[gate] {
                    gateState.failGate(id, result: GateResult(passed: false, gateName: gate, error: error), errorCount: 1, elapsed: 0)
                    terminalManager?.logError("  ✖ [Gate: \(gate)] Failed: \(error)")
                }
            }
        }

        terminalManager?.logOutput("[Certification Complete] All active gates certified.")
        return passedCount
    }

    /// Clear the entire thread.
    public func clearThread() {
        messages.removeAll()
        gateState = GatePipelineState()
        isGenerating = false
        isLoadingSkeleton = true
        lastStreamingMessageID = nil
        meteringState.reset()
    }

    /// Delete a specific message.
    public func deleteMessage(id: String) {
        messages.removeAll { $0.id == id }
    }

    // MARK: - Placeholder Data

    private func loadPlaceholderMessages() {
        // Show loading skeleton initially; cleared when real messages arrive.
    }
}
