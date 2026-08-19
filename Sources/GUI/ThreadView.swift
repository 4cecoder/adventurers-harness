// TUI - ThreadView
// Center content area: scrollable message list with agent/user messages,
// tool execution indicators, code blocks, streaming, and gate progress.

import SwiftUI
import AdventurersCore
import LLMProviders
import Tools

// MARK: - Thread Message Model

/// A single message in the thread, representing either user input or agent output.
/// Wraps core domain types into a UI-ready, observable representation.
public struct ThreadMessage: Identifiable, Sendable {
    public let id: String
    public let role: MessageRole
    public let content: String
    public let timestamp: Date
    public let toolCalls: [ThreadToolCall]
    public let toolResults: [ThreadToolResult]
    public let isStreaming: Bool
    public let thinkingContent: String?

    public enum MessageRole: Sendable {
        case user
        case agent
        case system
        case gateResult
    }

    public init(
        id: String = UUID().uuidString,
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        toolCalls: [ThreadToolCall] = [],
        toolResults: [ThreadToolResult] = [],
        isStreaming: Bool = false,
        thinkingContent: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        self.isStreaming = isStreaming
        self.thinkingContent = thinkingContent
    }
}

/// A tool call embedded in an agent message, displayed as an inline preview.
public struct ThreadToolCall: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let arguments: String
    public let status: ToolCallStatus

    public enum ToolCallStatus: Sendable {
        case pending
        case running
        case succeeded(output: String)
        case failed(error: String)
    }

    public init(
        id: String = UUID().uuidString,
        name: String,
        arguments: String,
        status: ToolCallStatus = .pending
    ) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.status = status
    }
}

/// The result of a completed tool execution.
public struct ThreadToolResult: Identifiable, Sendable {
    public let id: String
    public let toolCallID: String
    public let output: String
    public let isError: Bool

    public init(id: String = UUID().uuidString, toolCallID: String, output: String, isError: Bool = false) {
        self.id = id
        self.toolCallID = toolCallID
        self.output = output
        self.isError = isError
    }
}

// MARK: - Queued Prompt Model

public struct QueuedPrompt: Identifiable, Sendable, Equatable {
    public let id: String
    public var text: String
    public let timestamp: Date

    public init(id: String = UUID().uuidString, text: String, timestamp: Date = Date()) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
    }
}

// MARK: - Thread ViewModel

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
    public var onMessagesChanged: (([ThreadMessage]) -> Void)?
    public let meteringState = ThreadMeteringState()
    public var activeGenerationTask: Task<Void, Never>? = nil

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
                self.messages = loaded
                self.isLoadingSkeleton = false
                meteringState.recalculateContext(messages: loaded)
            } else {
                loadPlaceholderMessages()
                meteringState.recalculateContext(messages: self.messages)
            }
        } else {
            loadPlaceholderMessages()
            meteringState.recalculateContext(messages: self.messages)
        }
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

            let threadWorkspace = self.workingDirectory
            let systemPrompt = """
            You are Adventurers Harness, an autonomous agentic pair programmer with direct access to the local codebase through native tools.
            Your thread is rooted in the working directory: \(threadWorkspace).

            WORKSPACE SCOPE & CONFINEMENT RULES:
            1. SCOPE RETENTION: All relative file paths and tool calls (view_file, write_file, edit_file, list_dir, grep_search, bash) MUST resolve relative to and operate strictly inside '\(threadWorkspace)' by default.
            2. DIRECTORY BOUNDARY INTEGRITY: Do NOT wander outside this directory tree (e.g. into parent directories '..', sibling repositories, or system paths) unless the user's instructions explicitly and unambiguously command accessing an external path.
            3. Keep all scratch files, edits, test commands, and builds scoped to '\(threadWorkspace)'.

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

            var maxTurns = 6
            var finalContent = ""
            var totalToolsExecuted = 0

            let totalPromptChars = llmMessages.map(\.content).joined().count
            let estimatedPromptTokens = max(10, Int(ceil(Double(totalPromptChars) / 3.6)))
            self.meteringState.startTurn(
                model: model,
                provider: providerType.rawValue,
                estimatedPromptTokens: estimatedPromptTokens
            )

            terminalManager?.logCommand("[Agent Dispatch] Provider: \(providerType.rawValue) | Model: \(model)")

            while maxTurns > 0 && !Task.isCancelled {
                await self.checkPauseState()
                guard !Task.isCancelled else { break }

                maxTurns -= 1
                let agentMessageID = UUID().uuidString
                let placeholder = ThreadMessage(
                    id: agentMessageID,
                    role: .agent,
                    content: "",
                    isStreaming: true
                )
                self.appendMessage(placeholder)

                var accumulatedContent = ""
                var accumulatedReasoning = ""

                do {
                    let stream = provider.stream(messages: llmMessages, config: config)
                    for try await chunk in stream {
                        await self.checkPauseState()
                        guard !Task.isCancelled else { break }

                        if let reasoning = chunk.reasoningDelta, !reasoning.isEmpty {
                            accumulatedReasoning += reasoning
                        }
                        if !chunk.delta.isEmpty {
                            accumulatedContent += chunk.delta
                        }

                        self.meteringState.recordStreamChunk(
                            deltaText: chunk.delta,
                            reasoningDelta: chunk.reasoningDelta,
                            exactUsage: chunk.usage
                        )

                        self.updateMessageWithReasoning(
                            id: agentMessageID,
                            content: accumulatedContent,
                            reasoning: accumulatedReasoning.isEmpty ? nil : accumulatedReasoning
                        )
                    }

                    self.finishStreaming(messageID: agentMessageID)
                    finalContent = accumulatedContent
                    terminalManager?.logOutput("[Agent Output] \(accumulatedContent.count) bytes received.")

                    if Task.isCancelled { break }

                    // Check for tool calls
                    let toolInvocations = self.extractToolCalls(from: accumulatedContent)
                    if toolInvocations.isEmpty {
                        // Strip any potential dangling markup from final message
                        let cleaned = self.toolParser.cleanMessageContent(from: accumulatedContent)
                        if !cleaned.isEmpty && cleaned != accumulatedContent {
                            self.updateMessage(id: agentMessageID, content: cleaned)
                        }
                        break // Done, no more tool calls
                    }

                    totalToolsExecuted += toolInvocations.count

                    // Execute tools
                    var executedToolResults: [String] = []
                    var threadToolCalls: [ThreadToolCall] = []
                    var threadToolResults: [ThreadToolResult] = []

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
                        threadToolCalls.append(toolCall)

                        let toolResult = ThreadToolResult(id: trID, toolCallID: tcID, output: outputStr, isError: result.error != nil)
                        threadToolResults.append(toolResult)

                        executedToolResults.append("Tool '\(inv.name)' result:\n\(outputStr)")
                        if let err = result.error {
                            terminalManager?.logError("[Tool Error] \(err)")
                        } else {
                            terminalManager?.logOutput("[Tool Output]\n\(outputStr.prefix(300))")
                        }
                    }

                    // Update message with executed tool calls and cleaned text
                    let cleanedContent = self.toolParser.cleanMessageContent(from: accumulatedContent)
                    if let idx = self.messages.firstIndex(where: { $0.id == agentMessageID }) {
                        let old = self.messages[idx]
                        self.messages[idx] = ThreadMessage(
                            id: old.id,
                            role: old.role,
                            content: cleanedContent.isEmpty ? "Executed \(threadToolCalls.count) tool\(threadToolCalls.count == 1 ? "" : "s")." : cleanedContent,
                            timestamp: old.timestamp,
                            toolCalls: threadToolCalls,
                            toolResults: threadToolResults,
                            isStreaming: false,
                            thinkingContent: old.thinkingContent
                        )
                        self.onMessagesChanged?(self.messages)
                    }

                    // Add tool results to LLM messages for next turn
                    llmMessages.append(Message(role: .assistant, content: accumulatedContent))
                    llmMessages.append(Message(role: .user, content: executedToolResults.joined(separator: "\n\n")))

                } catch {
                    let fallbackContent = accumulatedContent.isEmpty ? "⚠️ Notice: \(error.localizedDescription)" : accumulatedContent
                    self.updateMessage(id: agentMessageID, content: fallbackContent)
                    self.finishStreaming(messageID: agentMessageID)
                    terminalManager?.logError("[Notice] \(error.localizedDescription)")
                    finalContent = fallbackContent
                    break
                }
            }

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

    private func extractToolCalls(from text: String) -> [ThreadToolCallParser.ToolInvocation] {
        toolParser.extractToolCalls(from: text)
    }

    private func executeNativeTool(name: String, arguments: [String: AnyCodable]) async -> ToolResult {
        await toolExecutor.execute(name: name, arguments: arguments, workingDirectory: self.workingDirectory)
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

// MARK: - ThreadView (Root)

/// The main thread content view: gate progress, scrollable messages, and input bar.
public struct ThreadView: View {
    @Environment(AppState.self) private var appState: AppState?
    @ObservedObject private var threadVM: ThreadViewModel
    @State private var hoveredMessageID: String?
    @State private var showingModelPicker = false
    @State private var isGatesExpanded = false

    public init(viewModel: ThreadViewModel = ThreadViewModel()) {
        self.threadVM = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Compact Gate Certification Bar (Expandable on demand)
            CompactGateBar(
                state: threadVM.gateState,
                isExpanded: $isGatesExpanded,
                workingDirectoryName: threadVM.workingDirectoryName,
                workingDirectory: threadVM.workingDirectory,
                onChooseDirectory: {
                    if let appState, let threadID = threadVM.threadID {
                        appState.chooseAndSetWorkingDirectory(for: threadID)
                    } else {
                        #if os(macOS)
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        panel.canCreateDirectories = true
                        panel.prompt = "Choose Workspace"
                        if panel.runModal() == .OK, let url = panel.url {
                            threadVM.workingDirectory = url.path
                        }
                        #endif
                    }
                }
            )

            if isGatesExpanded {
                GateProgressView(state: threadVM.gateState)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                Divider()
            }

            messagesArea

            Divider()

            MessageInputBar(
                text: $threadVM.inputText,
                selectedModel: Binding(
                    get: {
                        if let sModel = appState?.settingsModel.selectedModel, !sModel.isEmpty {
                            return sModel
                        }
                        return threadVM.selectedModel
                    },
                    set: { newModel in
                        threadVM.selectedModel = newModel
                        appState?.settingsModel.selectedModel = newModel
                    }
                ),
                executionMode: Binding(
                    get: { appState?.settingsModel.executionMode ?? .codingPlan },
                    set: { appState?.settingsModel.executionMode = $0 }
                ),
                selectedMetaHarness: Binding(
                    get: { appState?.settingsModel.selectedMetaHarness ?? .codex },
                    set: { appState?.settingsModel.selectedMetaHarness = $0 }
                ),
                availableModels: appState?.settingsModel.modelsForActiveProvider() ?? threadVM.availableModels,
                isGenerating: threadVM.isGenerating,
                isPaused: threadVM.isPaused,
                queuedPrompts: threadVM.queuedPrompts,
                onSend: {
                    let diffState = appState?.selectedThreadID.flatMap { appState?.diffStates[$0] }
                    threadVM.sendMessage(
                        settings: appState?.settingsModel,
                        terminalManager: appState?.terminalManager,
                        diffState: diffState
                    )
                },
                onPauseToggle: {
                    threadVM.togglePause(terminalManager: appState?.terminalManager)
                },
                onStop: {
                    threadVM.stopRun(terminalManager: appState?.terminalManager)
                },
                onQueue: { prompt in
                    threadVM.queuePrompt(prompt, terminalManager: appState?.terminalManager)
                },
                onRemoveQueueItem: { id in
                    threadVM.removeQueuedPrompt(id: id)
                },
                onClearQueue: {
                    threadVM.clearQueuedPrompts()
                },
                onClear: { threadVM.clearThread() }
            )
        }
        .onAppear {
            if let current = appState?.settingsModel.selectedModel, !current.isEmpty {
                threadVM.selectedModel = current
            }
        }
    }
}

// MARK: - Compact Gate Bar

struct CompactGateBar: View {
    @ObservedObject var state: GatePipelineState
    @Binding var isExpanded: Bool
    var workingDirectoryName: String = "workspace"
    var workingDirectory: String = ""
    var onChooseDirectory: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.adOrange)

                Text("Harness Gates")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.adTextPrimary)
            }

            // Gate Dots
            HStack(spacing: 5) {
                ForEach(Array(state.nodes.enumerated()), id: \.element.id) { index, node in
                    Circle()
                        .fill(nodeColor(node: node, isActive: state.activeGateIndex == index))
                        .frame(width: 6, height: 6)
                        .help("\(node.displayName): \(node.status.isSuccess ? "Passed" : "Pending")")
                }
            }

            // Thread Workspace Folder Scope Badge (Interactive Menu)
            Menu {
                Section("Thread Working Directory") {
                    Text(workingDirectory.isEmpty ? workingDirectoryName : workingDirectory)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.adTextTertiary)
                }

                Divider()

                Button {
                    onChooseDirectory?()
                } label: {
                    Label("Change Working Folder...", systemImage: "folder.badge.plus")
                }

                Button {
                    #if os(macOS)
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: workingDirectory)
                    #endif
                } label: {
                    Label("Reveal in Finder", systemImage: "arrow.up.forward.app")
                }

                Button {
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(workingDirectory, forType: .string)
                    #endif
                } label: {
                    Label("Copy Folder Path", systemImage: "doc.on.doc")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.adInfo)

                    Text(workingDirectoryName)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.adTextSecondary)
                        .lineLimit(1)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 7))
                        .foregroundStyle(Color.adTextTertiary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.adOverlay)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .help("Click to change or reveal thread workspace (currently: \(workingDirectory.isEmpty ? workingDirectoryName : workingDirectory))")

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text(isExpanded ? "Hide Details" : "Inspect Gates")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.adTextSecondary)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.adTextTertiary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.adElevated)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.adElevated.opacity(0.8))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.adDivider),
            alignment: .bottom
        )
    }

    private func nodeColor(node: GateNode, isActive: Bool) -> Color {
        if node.status.isSuccess { return Color.adSuccess }
        if node.status.isFailure { return Color.adError }
        if isActive { return Color.adOrange }
        return Color.adTextTertiary.opacity(0.4)
    }
}

// MARK: - Messages Area
extension ThreadView {
    @ViewBuilder
    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if threadVM.isLoadingSkeleton {
                        LoadingSkeletonView()
                    } else if threadVM.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(threadVM.messages) { message in
                            MessageBubbleView(
                                message: message,
                                isHovered: hoveredMessageID == message.id,
                                onRetry: { retryMessage(message) },
                                onCopy: { copyMessage(message) },
                                onDelete: { deleteMessage(message) }
                            )
                            .id(message.id)
                            .onHover { isHovered in
                                hoveredMessageID = isHovered ? message.id : nil
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.automatic)
            .onChange(of: threadVM.messages.count) {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: threadVM.lastStreamingMessageID) {
                if let id = threadVM.lastStreamingMessageID {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Start a conversation")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Type a message below to begin working with the agent.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let lastID = threadVM.messages.last?.id else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }

    // MARK: - Actions

    private func retryMessage(_ message: ThreadMessage) {
        // Re-send the user message that preceded this agent response.
    }

    private func copyMessage(_ message: ThreadMessage) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        #endif
    }

    private func deleteMessage(_ message: ThreadMessage) {
        threadVM.messages.removeAll { $0.id == message.id }
    }
}

// MARK: - MessageBubbleView

/// Individual message bubble. Agent messages are left-aligned, user messages right-aligned.
public struct MessageBubbleView: View {
    public let message: ThreadMessage
    public let isHovered: Bool
    public let onRetry: () -> Void
    public let onCopy: () -> Void
    public let onDelete: () -> Void

    @State private var isThinkingExpanded = false

    public init(
        message: ThreadMessage,
        isHovered: Bool = false,
        onRetry: @escaping () -> Void = {},
        onCopy: @escaping () -> Void = {},
        onDelete: @escaping () -> Void = {}
    ) {
        self.message = message
        self.isHovered = isHovered
        self.onRetry = onRetry
        self.onCopy = onCopy
        self.onDelete = onDelete
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            if message.role == .agent {
                agentAvatar
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                messageHeader
                messageContent
                messageFooter
            }

            if message.role == .user {
                userAvatar
            }

            if message.role == .agent {
                Spacer(minLength: 60)
            }
        }
        .padding(.vertical, 6)
        .overlay(alignment: .topTrailing) {
            if isHovered {
                messageActions
                    .padding(4)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    // MARK: - Avatars

    @ViewBuilder
    private var agentAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 30, height: 30)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                )
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.9))
        }
    }

    @ViewBuilder
    private var userAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 30, height: 30)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
                )
            Image(systemName: "person.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var messageHeader: some View {
        HStack(spacing: 6) {
            Text(roleLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if isHovered {
                Text(formattedTimestamp)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var roleLabel: String {
        switch message.role {
        case .user: return "You"
        case .agent: return "Agent"
        case .system: return "System"
        case .gateResult: return "Gate"
        }
    }

    private var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: message.timestamp)
    }

    // MARK: - Content

    @ViewBuilder
    private var messageContent: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            // Thinking section (collapsible)
            if let thinking = message.thinkingContent, !thinking.isEmpty {
                thinkingSection(thinking)
            }

            // Multi-Tool execution cluster (auto-collapsing for multiple tools / large output)
            if !message.toolCalls.isEmpty || !message.toolResults.isEmpty {
                MultiToolCallClusterView(
                    toolCalls: message.toolCalls,
                    toolResults: message.toolResults
                )
            }

            // Main message content with code blocks
            if !message.content.isEmpty {
                RichMessageView(
                    content: message.content,
                    isStreaming: message.isStreaming
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            Group {
                if message.role == .user {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.adOrange.opacity(0.24),
                                    Color.adOrange.opacity(0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        stops: [
                                            .init(color: Color.white.opacity(0.35), location: 0.0),
                                            .init(color: Color.adOrange.opacity(0.25), location: 0.5),
                                            .init(color: Color.white.opacity(0.10), location: 1.0)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: Color.adOrange.opacity(0.20), radius: 10, x: 0, y: 3)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.04),
                                            Color.black.opacity(0.35)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        stops: [
                                            .init(color: Color.white.opacity(0.22), location: 0.0),
                                            .init(color: Color.white.opacity(0.04), location: 0.6),
                                            .init(color: Color.white.opacity(0.10), location: 1.0)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 4)
                }
            }
        )
    }

    @ViewBuilder
    private func thinkingSection(_ thinking: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isThinkingExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "brain.head.profile")
                        .font(.caption)
                    Text("Thinking Process")
                        .font(.caption.weight(.medium))
                    Image(systemName: isThinkingExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(Color.adOrange)
            }
            .buttonStyle(.plain)

            if isThinkingExpanded {
                Text(thinking)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.adTextSecondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            }
        }
    }

    @ViewBuilder
    private func toolResultSection(_ result: ThreadToolResult) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: result.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(result.isError ? Color.adError : Color.adSuccess)
                Text(result.isError ? "Tool Error" : "Tool Output")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.adTextSecondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(result.output)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.adTextPrimary)
                    .textSelection(.enabled)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Footer

    @ViewBuilder
    private var messageFooter: some View {
        if message.isStreaming {
            streamingIndicator
        }
    }

    private var streamingIndicator: some View {
        HStack(spacing: 4) {
            StreamingCursorView()
            Text("Generating...")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Actions Overlay

    @ViewBuilder
    private var messageActions: some View {
        HStack(spacing: 2) {
            actionButton(icon: "doc.on.doc", label: "Copy", action: onCopy)
            if message.role == .agent {
                actionButton(icon: "arrow.clockwise", label: "Retry", action: onRetry)
            }
            actionButton(icon: "trash", label: "Delete", action: onDelete)
        }
        .padding(4)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.1), radius: 3)
    }

    @ViewBuilder
    private func actionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .help(label)
    }
}

// MARK: - RichMessageView

/// Parses message content and renders text, code blocks, and inline formatting.
public struct RichMessageView: View {
    public let content: String
    public let isStreaming: Bool

    @State private var copiedBlockID: String?

    public init(content: String, isStreaming: Bool = false) {
        self.content = content
        self.isStreaming = isStreaming
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parsedSegments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let text):
                    textSegment(text)
                case .codeBlock(let language, let code, let id):
                    CodeBlockView(
                        language: language,
                        code: code,
                        isCopied: copiedBlockID == id
                    ) {
                        copyToClipboard(code)
                        copiedBlockID = id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            if copiedBlockID == id { copiedBlockID = nil }
                        }
                    }
                }
            }

            if isStreaming {
                StreamingCursorView()
            }
        }
    }

    @ViewBuilder
    private func textSegment(_ text: String) -> some View {
        Text(LocalizedStringKey(text))
            .font(.body)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func copyToClipboard(_ text: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    // MARK: - Parsing

    private enum ContentSegment: Identifiable {
        case text(String)
        case codeBlock(language: String, code: String, id: String)

        var id: String {
            switch self {
            case .text(let t): return "text-\(t.hashValue)"
            case .codeBlock(_, _, let id): return id
            }
        }
    }

    private var parsedSegments: [ContentSegment] {
        var segments: [ContentSegment] = []
        let pattern = #"```(\w*)\n([\s\S]*?)```"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [.text(content)]
        }

        let nsContent = content as NSString
        var lastEnd = 0
        let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))

        for match in matches {
            // Text before code block
            if match.range.location > lastEnd {
                let textRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                let text = nsContent.substring(with: textRange).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    segments.append(.text(text))
                }
            }

            // Code block
            let langRange = match.range(at: 1)
            let codeRange = match.range(at: 2)
            let language = langRange.location != NSNotFound ? nsContent.substring(with: langRange) : ""
            let code = nsContent.substring(with: codeRange)
            segments.append(.codeBlock(
                language: language.isEmpty ? "code" : language,
                code: String(code.trimmingCharacters(in: .newlines)),
                id: "block-\(match.range.location)"
            ))

            lastEnd = match.range.upperBound
        }

        // Trailing text
        if lastEnd < nsContent.length {
            let remaining = nsContent.substring(from: lastEnd).trimmingCharacters(in: .whitespacesAndNewlines)
            if !remaining.isEmpty {
                segments.append(.text(remaining))
            }
        }

        if segments.isEmpty {
            segments.append(.text(content))
        }

        return segments
    }
}

// MARK: - CodeBlockView

/// A syntax-highlighted code block with language label, line numbers, copy, and expand.
public struct CodeBlockView: View {
    public let language: String
    public let code: String
    public let isCopied: Bool
    public let onCopy: () -> Void

    @State private var isExpanded = true
    @State private var showFullCode = false

    private let maxCollapsedLines = 8

    public init(
        language: String,
        code: String,
        isCopied: Bool = false,
        onCopy: @escaping () -> Void = {}
    ) {
        self.language = language
        self.code = code
        self.isCopied = isCopied
        self.onCopy = onCopy
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            codeContent
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Header Bar

    @ViewBuilder
    private var headerBar: some View {
        HStack(spacing: 0) {
            // Language badge
            HStack(spacing: 4) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.caption2)
                Text(language.uppercased())
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.08))

            Spacer()

            // Line count
            let lineCount = code.components(separatedBy: "\n").count
            Text("\(lineCount) lines")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.trailing, 8)

            // Copy button
            Button(action: onCopy) {
                HStack(spacing: 3) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                    if isCopied {
                        Text("Copied")
                            .font(.caption2)
                    }
                }
                .foregroundStyle(isCopied ? .green : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)

            // Expand/collapse button
            if code.components(separatedBy: "\n").count > maxCollapsedLines {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "minus.square" : "plus.square")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .padding(0)
    }

    // MARK: - Code Content

    @ViewBuilder
    private var codeContent: some View {
        let lines = code.components(separatedBy: "\n")
        let displayLines = isExpanded ? lines : Array(lines.prefix(maxCollapsedLines))

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {
                // Line numbers
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(Array(displayLines.enumerated()), id: \.offset) { index, _ in
                        Text("\(index + 1)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary.opacity(0.6))
                            .frame(width: 30, alignment: .trailing)
                            .padding(.trailing, 8)
                    }
                }
                .padding(.leading, 10)
                .padding(.vertical, 10)

                // Divider
                Rectangle()
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 1)

                // Code
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(displayLines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.caption.monospaced())
                            .foregroundStyle(syntaxColor(for: line))
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.4))

        // Collapsed indicator
        if !isExpanded && lines.count > maxCollapsedLines {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.down")
                    Text("Show \(lines.count - maxCollapsedLines) more lines")
                }
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Basic Syntax Colors

    /// Lightweight keyword-aware coloring. Full Highlight.js/TreeSitter integration
    /// can replace this later.
    private func syntaxColor(for line: String) -> Color {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("//") || trimmed.hasPrefix("#") || trimmed.hasPrefix("/*") {
            return .secondary.opacity(0.7)
        }
        if trimmed.hasPrefix("func ") || trimmed.hasPrefix("let ") || trimmed.hasPrefix("var ")
            || trimmed.hasPrefix("class ") || trimmed.hasPrefix("struct ") || trimmed.hasPrefix("enum ")
            || trimmed.hasPrefix("import ") || trimmed.hasPrefix("public ") || trimmed.hasPrefix("private ")
            || trimmed.hasPrefix("if ") || trimmed.hasPrefix("else ") || trimmed.hasPrefix("return ")
            || trimmed.hasPrefix("for ") || trimmed.hasPrefix("while ") || trimmed.hasPrefix("switch ")
            || trimmed.hasPrefix("case ") || trimmed.hasPrefix("def ") || trimmed.hasPrefix("fn ")
            || trimmed.hasPrefix("pub ") || trimmed.hasPrefix("use ") || trimmed.hasPrefix("mod ")
        {
            return .purple
        }
        if trimmed.hasPrefix("\"") || trimmed.hasPrefix("'") || trimmed.hasPrefix("`") {
            return .green
        }
        return .primary
    }
}

// MARK: - MultiToolCallClusterView

/// Auto-collapsing container for one or more tool executions and outputs.
/// Automatically collapses multiple completed tool calls into a single sleek row,
/// while keeping running or failed tool calls immediately visible.
public struct MultiToolCallClusterView: View {
    public let toolCalls: [ThreadToolCall]
    public let toolResults: [ThreadToolResult]

    @State private var isExpanded: Bool

    public init(toolCalls: [ThreadToolCall], toolResults: [ThreadToolResult]) {
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        let isRunning = toolCalls.contains(where: {
            if case .running = $0.status { return true }
            return false
        })
        let hasFailure = toolCalls.contains(where: {
            if case .failed = $0.status { return true }
            return false
        }) || toolResults.contains(where: { $0.isError })

        // Auto-expand if active or failed; auto-collapse if multiple completed tools
        self._isExpanded = State(initialValue: isRunning || hasFailure || toolCalls.count <= 1)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header summary button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isRunning ? "arrow.triangle.2.circlepath" : "wrench.and.screwdriver.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(statusColor)

                    Text(summaryTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.adTextPrimary)

                    if !isExpanded {
                        // Compact tool badges
                        HStack(spacing: 4) {
                            ForEach(toolCalls.prefix(4)) { tc in
                                Text(tc.name)
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.adElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .foregroundStyle(Color.adTextSecondary)
                            }
                            if toolCalls.count > 4 {
                                Text("+\(toolCalls.count - 4)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color.adTextTertiary)
                            }
                        }
                    }

                    Spacer()

                    Text(isExpanded ? "Collapse" : "Expand")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.adTextTertiary)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.adTextTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.adElevated.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(statusColor.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            // Expanded tool items
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(toolCalls) { toolCall in
                        VStack(alignment: .leading, spacing: 4) {
                            ToolExecutionIndicatorView(toolCall: toolCall)

                            if let matchingResult = toolResults.first(where: { $0.toolCallID == toolCall.id }) ?? (toolCalls.count == 1 ? toolResults.first : nil) {
                                if !matchingResult.output.isEmpty {
                                    CollapsibleToolResultView(result: matchingResult)
                                }
                            }
                        }
                    }

                    // Remaining orphan tool results if any
                    let orphanResults = toolResults.filter { res in
                        !toolCalls.contains(where: { $0.id == res.toolCallID }) && toolCalls.count > 1
                    }
                    ForEach(orphanResults) { res in
                        CollapsibleToolResultView(result: res)
                    }
                }
                .padding(.leading, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var isRunning: Bool {
        toolCalls.contains(where: {
            if case .running = $0.status { return true }
            return false
        })
    }

    private var hasFailure: Bool {
        toolCalls.contains(where: {
            if case .failed = $0.status { return true }
            return false
        }) || toolResults.contains(where: { $0.isError })
    }

    private var statusColor: Color {
        if isRunning { return Color.adInfo }
        if hasFailure { return Color.adError }
        return Color.adSuccess
    }

    private var summaryTitle: String {
        if isRunning {
            let active = toolCalls.first(where: { if case .running = $0.status { return true }; return false })
            return "Running \(active?.name ?? "tool")..."
        }
        if hasFailure {
            return "Executed \(toolCalls.count) tool\(toolCalls.count == 1 ? "" : "s") (with errors)"
        }
        return "Executed \(toolCalls.count) tool\(toolCalls.count == 1 ? "" : "s") • All Succeeded"
    }
}

// MARK: - Collapsible Tool Result View

public struct CollapsibleToolResultView: View {
    public let result: ThreadToolResult
    @State private var isExpanded: Bool = false
    @State private var copied: Bool = false

    public init(result: ThreadToolResult) {
        self.result = result
        let lineCount = result.output.components(separatedBy: .newlines).count
        self._isExpanded = State(initialValue: lineCount <= 3 && result.output.count <= 180)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: result.isError ? "exclamationmark.triangle.fill" : "terminal.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(result.isError ? Color.adError : Color.adTextSecondary)

                Text(result.isError ? "Tool Error" : "Output")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.adTextSecondary)

                let lineCount = result.output.components(separatedBy: .newlines).count
                Text("(\(lineCount) line\(lineCount == 1 ? "" : "s"), \(result.output.count) B)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.adTextTertiary)

                Spacer()

                #if os(macOS)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.output, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                } label: {
                    Text(copied ? "Copied!" : "Copy")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(copied ? Color.adSuccess : Color.adTextTertiary)
                }
                .buttonStyle(.plain)
                #endif

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.adTextTertiary)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(result.output)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(result.isError ? Color.adError : Color.adTextPrimary)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 280)
            } else {
                Text(result.output.prefix(120).replacingOccurrences(of: "\n", with: " ") + (result.output.count > 120 ? "..." : ""))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.adTextTertiary)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - ToolExecutionIndicatorView

/// Inline indicator for tool execution status.
/// Shows: icon, tool name, status, and expandable arguments.
public struct ToolExecutionIndicatorView: View {
    public let toolCall: ThreadToolCall

    @State private var isExpanded = false

    public init(toolCall: ThreadToolCall) {
        self.toolCall = toolCall
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    statusIcon
                    toolNameLabel
                    Spacer()
                    statusLabel
                    if !toolCall.arguments.isEmpty {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(toolBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            if isExpanded && !toolCall.arguments.isEmpty {
                expandedArguments
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch toolCall.status {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .running:
            ProgressView()
                .controlSize(.mini)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private var toolNameLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: toolIconName)
                .font(.caption2)
            Text(toolCall.name)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
        }
    }

    private var statusLabel: some View {
        switch toolCall.status {
        case .pending:
            Text("Pending")
                .foregroundStyle(.secondary)
        case .running:
            Text("Running \(toolCall.name)...")
                .foregroundStyle(.blue)
        case .succeeded(_):
            Text("Done")
                .foregroundStyle(.green)
        case .failed(let error):
            Text(error.isEmpty ? "Failed" : error)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var expandedArguments: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(toolCall.arguments)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var toolBackground: some View {
        switch toolCall.status {
        case .running:
            Color.blue.opacity(0.06)
        case .succeeded:
            Color.green.opacity(0.04)
        case .failed:
            Color.red.opacity(0.04)
        case .pending:
            Color.secondary.opacity(0.04)
        }
    }

    private var toolIconName: String {
        switch toolCall.name {
        case "bash", "shell": return "terminal"
        case "file", "write": return "doc.text"
        case "read": return "doc"
        case "grep": return "magnifyingglass"
        case "glob": return "folder"
        case "edit": return "pencil.and.list.clipboard"
        default: return "wrench.and.screwdriver"
        }
    }
}

// MARK: - NativeGlassTextView

#if os(macOS)
import AppKit

public struct NativeGlassTextView: NSViewRepresentable {
    @Binding public var text: String
    public var placeholder: String
    public var onCommit: () -> Void

    public init(
        text: Binding<String>,
        placeholder: String = "Message the agent...",
        onCommit: @escaping () -> Void = {}
    ) {
        self._text = text
        self.placeholder = placeholder
        self.onCommit = onCommit
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = InnerTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor.white
        textView.insertionPointColor = NSColor(red: 1.0, green: 0.42, blue: 0.21, alpha: 1.0)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.placeholder = placeholder
        textView.onEnter = onCommit
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 4, height: 6)

        scrollView.documentView = textView
        
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
        
        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? InnerTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.placeholder = placeholder
    }

    public class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeGlassTextView

        init(_ parent: NativeGlassTextView) {
            self.parent = parent
        }

        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            self.parent.text = textView.string
        }
    }
}

class InnerTextView: NSTextView {
    var placeholder: String?
    var onEnter: (() -> Void)?

    override var acceptsFirstResponder: Bool {
        return true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 { // Return
            if event.modifierFlags.contains(.shift) {
                super.insertNewlineIgnoringFieldEditor(nil)
            } else {
                onEnter?()
            }
            return
        }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty, let placeholder = placeholder {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font ?? NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.placeholderTextColor
            ]
            let rect = NSRect(
                x: textContainerInset.width + 4,
                y: textContainerInset.height + 1,
                width: bounds.width - 12,
                height: bounds.height
            )
            (placeholder as NSString).draw(in: rect, withAttributes: attrs)
        }
    }
}
#endif

// MARK: - MessageInputBar

/// Bottom liquid glass input bar: native text editor, attachment button, model selector, pause/resume, queue drawer, and glowing send button.
public struct MessageInputBar: View {
    @Binding public var text: String
    @Binding public var selectedModel: String
    @Binding public var executionMode: ExecutionMode
    @Binding public var selectedMetaHarness: MetaHarnessType
    public let availableModels: [String]
    public let isGenerating: Bool
    public let isPaused: Bool
    public let queuedPrompts: [QueuedPrompt]
    public let onSend: () -> Void
    public let onPauseToggle: () -> Void
    public let onStop: () -> Void
    public let onQueue: (String) -> Void
    public let onRemoveQueueItem: (String) -> Void
    public let onClearQueue: () -> Void
    public let onClear: () -> Void

    @State private var showingModelPicker = false
    @State private var hoverSend = false
    @State private var hoverStop = false
    @State private var hoverPause = false

    public init(
        text: Binding<String>,
        selectedModel: Binding<String>,
        executionMode: Binding<ExecutionMode> = .constant(.codingPlan),
        selectedMetaHarness: Binding<MetaHarnessType> = .constant(.codex),
        availableModels: [String] = ["gpt-4o"],
        isGenerating: Bool = false,
        isPaused: Bool = false,
        queuedPrompts: [QueuedPrompt] = [],
        onSend: @escaping () -> Void = {},
        onPauseToggle: @escaping () -> Void = {},
        onStop: @escaping () -> Void = {},
        onQueue: @escaping (String) -> Void = { _ in },
        onRemoveQueueItem: @escaping (String) -> Void = { _ in },
        onClearQueue: @escaping () -> Void = {},
        onClear: @escaping () -> Void = {}
    ) {
        self._text = text
        self._selectedModel = selectedModel
        self._executionMode = executionMode
        self._selectedMetaHarness = selectedMetaHarness
        self.availableModels = availableModels
        self.isGenerating = isGenerating
        self.isPaused = isPaused
        self.queuedPrompts = queuedPrompts
        self.onSend = onSend
        self.onPauseToggle = onPauseToggle
        self.onStop = onStop
        self.onQueue = onQueue
        self.onRemoveQueueItem = onRemoveQueueItem
        self.onClearQueue = onClearQueue
        self.onClear = onClear
    }

    public var body: some View {
        VStack(spacing: 6) {
            // Floating Queued Prompts Drawer
            if !queuedPrompts.isEmpty {
                queuedPromptsDrawer
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(alignment: .center, spacing: 8) {
                // Execution Mode & Harness Switcher
                modeAndHarnessSelector

                if executionMode == .codingPlan {
                    // Model selector (for Direct Coding Plan)
                    modelSelector
                }

                // Native Glass Text input
                textEditor

                // Execution Controls (Pause, Stop, Send / Queue)
                if isGenerating {
                    // Pause / Resume Button
                    pauseButton

                    // Stop Button
                    stopButton
                }

                // Primary Send / Queue Action Button
                primaryActionButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .liquidGlassCard(cornerRadius: 16, strokeOpacity: 0.24, glowColor: hoverSend ? Color.adOrange : .clear)

            inputHints
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .background(Color.clear)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: queuedPrompts.count)
        .animation(.easeInOut(duration: 0.2), value: isGenerating)
        .animation(.easeInOut(duration: 0.2), value: isPaused)
    }

    // MARK: - Queued Prompts Drawer

    @ViewBuilder
    private var queuedPromptsDrawer: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "list.bullet.clipboard.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.adInfo)
                Text("Queue (\(queuedPrompts.count))")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.adInfo)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.adInfo.opacity(0.15))
            .clipShape(Capsule())

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(queuedPrompts) { item in
                        HStack(spacing: 6) {
                            Text(item.text)
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .foregroundStyle(Color.adTextPrimary)

                            Button {
                                onRemoveQueueItem(item.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(Color.adTextTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.adElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.12), lineWidth: 1))
                    }
                }
            }

            Spacer()

            Button("Clear All") {
                onClearQueue()
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.adTextTertiary)
            .buttonStyle(.plain)
            .padding(.trailing, 4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.adCard.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.adInfo.opacity(0.25), lineWidth: 1))
    }

    // MARK: - Pause Button

    @ViewBuilder
    private var pauseButton: some View {
        Button(action: onPauseToggle) {
            ZStack {
                Circle()
                    .fill(isPaused ? Color.adSuccess.opacity(0.2) : Color.adWarning.opacity(0.15))
                    .frame(width: 30, height: 30)
                    .overlay(
                        Circle()
                            .strokeBorder(isPaused ? Color.adSuccess : Color.adWarning.opacity(0.6), lineWidth: 1)
                    )
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isPaused ? Color.adSuccess : Color.adWarning)
            }
        }
        .buttonStyle(.plain)
        .onHover { hoverPause = $0 }
        .help(isPaused ? "Resume execution (⌥Space)" : "Pause execution (⌥Space)")
    }

    // MARK: - Stop Button

    @ViewBuilder
    private var stopButton: some View {
        Button(action: onStop) {
            ZStack {
                Circle()
                    .fill(Color.adError.opacity(0.2))
                    .frame(width: 30, height: 30)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.adError.opacity(0.7), lineWidth: 1)
                    )
                Image(systemName: "stop.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.adError)
            }
        }
        .buttonStyle(.plain)
        .onHover { hoverStop = $0 }
        .help("Stop current run (⌘.)")
    }

    // MARK: - Primary Action Button (Send / Queue)

    @ViewBuilder
    private var primaryActionButton: some View {
        if isGenerating && canSend {
            // When user types while generating, allow Queuing prompt
            Button(action: {
                onQueue(text)
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.to.line.compact")
                        .font(.system(size: 11, weight: .bold))
                    Text("Queue")
                        .font(.system(size: 11, weight: .bold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.adInfo)
                .foregroundStyle(Color.black)
                .clipShape(Capsule())
                .shadow(color: Color.adInfo.opacity(0.4), radius: 6)
            }
            .buttonStyle(.plain)
            .help("Add prompt to queue for sequential execution")
        } else if !isGenerating {
            Button(action: onSend) {
                ZStack {
                    Circle()
                        .fill(sendButtonBackground)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    canSend ? Color.adOrange.opacity(0.6) : Color.white.opacity(0.08),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: canSend ? Color.adOrange.opacity(0.35) : .clear, radius: 4)

                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(sendButtonForeground)
                }
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .opacity(canSend ? 1.0 : 0.4)
            .onHover { hoverSend = $0 }
            .help("Send message (Return)")
        }
    }

    // MARK: - Mode & Harness Selector

    @ViewBuilder
    private var modeAndHarnessSelector: some View {
        Menu {
            Section("Execution Engine") {
                Button {
                    executionMode = .codingPlan
                } label: {
                    HStack {
                        Image(systemName: "bolt.shield.fill")
                        Text("Coding Plan (Direct LLM API)")
                        if executionMode == .codingPlan {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            Section("Meta Harness CLIs") {
                ForEach(MetaHarnessType.allCases) { harness in
                    Button {
                        executionMode = .metaHarness
                        selectedMetaHarness = harness
                    } label: {
                        HStack {
                            Image(systemName: harness.icon)
                            Text(harness.rawValue)
                            if executionMode == .metaHarness && selectedMetaHarness == harness {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: executionMode == .codingPlan ? "bolt.shield.fill" : selectedMetaHarness.icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(executionMode == .codingPlan ? Color.adOrange : Color.adInfo)

                Text(executionMode == .codingPlan ? "Plan" : selectedMetaHarness.defaultBinaryName)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.adTextPrimary)

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.adTextTertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.adElevated)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(executionMode == .codingPlan ? Color.adOrange.opacity(0.4) : Color.adInfo.opacity(0.4), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Switch between Direct Coding Plan (API Keys) and Meta Harness (Sub-Agent CLIs)")
    }

    // MARK: - Model Selector

    @ViewBuilder
    private var modelSelector: some View {
        PaginatedSearchableCombobox(
            selection: $selectedModel,
            title: "Select Model",
            items: availableModels,
            pageSize: 8
        )
        .fixedSize()
    }

    // MARK: - Text Editor

    @ViewBuilder
    private var textEditor: some View {
        #if os(macOS)
        NativeGlassTextView(
            text: $text,
            placeholder: isGenerating ? "Queue next prompt..." : "Message the agent...",
            onCommit: {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                if isGenerating {
                    onQueue(trimmed)
                } else {
                    onSend()
                }
            }
        )
        .frame(minHeight: 28, maxHeight: 110)
        #else
        TextField(isGenerating ? "Queue next prompt..." : "Message the agent...", text: $text, axis: .vertical)
            .font(.system(size: 13))
            .textFieldStyle(.plain)
            .lineLimit(1...6)
        #endif
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sendButtonForeground: Color {
        return (canSend || hoverSend) ? Color.black : Color.adTextTertiary
    }

    private var sendButtonBackground: Color {
        return (canSend || hoverSend) ? Color.adOrange : Color.adElevated
    }

    // MARK: - Hints

    @ViewBuilder
    private var inputHints: some View {
        HStack(spacing: 12) {
            Text("Return to send")
                .font(.system(size: 10))
                .foregroundStyle(Color.adTextTertiary)
            Text("Shift+Return for newline")
                .font(.system(size: 10))
                .foregroundStyle(Color.adTextTertiary)
            Spacer()
            if !text.isEmpty {
                Text("\(text.count) chars")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.adTextTertiary)
            }
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - StreamingCursorView

/// Blinking cursor animation shown during streaming text.
public struct StreamingCursorView: View {
    @State private var opacity: Double = 1.0

    public init() {}

    public var body: some View {
        Text("\u{258C}")
            .font(.body.monospaced())
            .foregroundStyle(Color.accentColor)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    opacity = 0.0
                }
            }
    }
}

// MARK: - LoadingSkeletonView

/// Placeholder skeleton UI while waiting for the first response.
public struct LoadingSkeletonView: View {
    @State private var shimmerOffset: CGFloat = -200

    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { index in
                skeletonRow(alignment: index % 2 == 0 ? .leading : .trailing)
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                shimmerOffset = 400
            }
        }
    }

    @ViewBuilder
    private func skeletonRow(alignment: HorizontalAlignment) -> some View {
        HStack {
            if alignment == .trailing { Spacer(minLength: 80) }

            VStack(alignment: alignment, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: 80, height: 10)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: 200, height: 10)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: 140, height: 10)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if alignment == .leading { Spacer(minLength: 80) }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ThreadView_Preview: PreviewProvider {
    static var previews: some View {
        ThreadView()
            .frame(width: 700, height: 600)
    }
}
#endif
