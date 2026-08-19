// ThreadView.swift
// Adventurers Harness — Modular Root Thread View with Gate Progress, Message Feed, and Glass Input Bar

import SwiftUI
import AdventurersCore
import LLMProviders

#if os(macOS)
import AppKit
#endif

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

            if let contract = threadVM.activeContract {
                TaskContractProgressCard(contract: contract, onRollback: {
                    Task {
                        await threadVM.rollbackLatestCheckpoint(terminalManager: appState?.terminalManager)
                    }
                })
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
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
                enableDictation: appState?.settingsModel.enableDictation ?? true,
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

// MARK: - Preview

#if DEBUG
struct ThreadView_Preview: PreviewProvider {
    static var previews: some View {
        ThreadView()
            .frame(width: 700, height: 600)
    }
}
#endif
