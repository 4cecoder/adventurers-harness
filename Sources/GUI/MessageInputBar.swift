// MessageInputBar.swift
// Adventurers Harness — Bottom Glass Input Bar, Native Text Editor, Attachment, and Queue Drawer

import SwiftUI
import AdventurersCore

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
    public let enableDictation: Bool
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

    @ObservedObject private var dictation = DictationManager.shared
    @State private var showingModelPicker = false
    @State private var hoverSend = false
    @State private var hoverStop = false
    @State private var hoverPause = false
    @State private var hoverDictate = false

    public init(
        text: Binding<String>,
        selectedModel: Binding<String>,
        executionMode: Binding<ExecutionMode> = .constant(.codingPlan),
        selectedMetaHarness: Binding<MetaHarnessType> = .constant(.codex),
        availableModels: [String] = ["gpt-4o"],
        enableDictation: Bool = true,
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
        self.enableDictation = enableDictation
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

                // Trailing Action Buttons (Dictation, Pause, Stop, Send)
                HStack(spacing: 8) {
                    // Talkies Minimal Single-Button Dictation (Optional & Configurable)
                    if enableDictation {
                        dictationButton
                    }

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
                .fixedSize()
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

    // MARK: - Talkies Minimal Dictation Button

    @ViewBuilder
    private var dictationButton: some View {
        Button(action: {
            dictation.toggleDictation(currentText: text) { updatedText in
                self.text = updatedText
            }
        }) {
            HStack(spacing: 5) {
                // Live RMS audio waveform meter when listening
                if dictation.state.isListening {
                    dictationWaveform
                        .transition(.scale.combined(with: .opacity))
                }

                ZStack {
                    // Pulsing glow when dictation is active
                    if dictation.state.isListening {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Color.red.opacity(0.6), Color.adOrange.opacity(0.0)],
                                    center: .center,
                                    startRadius: 4,
                                    endRadius: 20
                                )
                            )
                            .frame(width: 38, height: 38)
                    }

                    Circle()
                        .fill(dictationButtonBackground)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    dictation.state.isListening ? Color.red :
                                    (hoverDictate ? Color.adOrange : Color.adOrange.opacity(0.45)),
                                    lineWidth: 1.2
                                )
                        )
                        .shadow(color: dictation.state.isListening ? Color.red.opacity(0.6) : (hoverDictate ? Color.adOrange.opacity(0.3) : .clear), radius: 4)

                    Image(systemName: dictation.state.isListening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(dictationButtonForeground)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hoverDictate = $0 }
        .help(dictation.state.isListening ? "Stop dictation (Auto-formats punctuation)" : "Dictate prompt with Talkies Speech Engine")
        .animation(.easeInOut(duration: 0.2), value: dictation.state.isListening)
    }

    private var dictationButtonBackground: Color {
        if dictation.state.isListening {
            return Color.red.opacity(0.95)
        }
        return hoverDictate ? Color.adOrange.opacity(0.25) : Color.adOrange.opacity(0.12)
    }

    private var dictationButtonForeground: Color {
        if dictation.state.isListening {
            return Color.white
        }
        return Color.adOrange
    }

    @ViewBuilder
    private var dictationWaveform: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                let factor: CGFloat = [0.6, 1.0, 0.8, 0.5][index]
                let barHeight = max(4.0, CGFloat(dictation.audioLevel) * 20.0 * factor)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.adOrange)
                    .frame(width: 2.5, height: barHeight)
                    .animation(.spring(response: 0.15, dampingFraction: 0.6), value: dictation.audioLevel)
            }
        }
        .frame(height: 20)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Color.adCard.opacity(0.7))
        .clipShape(Capsule())
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
            if dictation.state.isListening {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                    Text("Dictating live • Say \"period\", \"comma\", \"new line\" • Click mic to stop")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.adOrange)
                }
            } else {
                Text("Return to send")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.adTextTertiary)
                Text("Shift+Return for newline")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.adTextTertiary)
            }
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
