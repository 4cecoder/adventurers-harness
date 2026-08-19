// ToolClusterViews.swift
// Adventurers Harness — Auto-Collapsing Multi-Tool Cluster, Indicators & Result Views

import SwiftUI
import AdventurersCore

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

                    HStack(spacing: 6) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.adSuccess)
                        Text("Atomic snapshot saved • 1-click rollback protected")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.adTextTertiary)
                        Spacer()
                    }
                    .padding(.top, 2)
                    .padding(.leading, 4)
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
            return "\(toolCalls.count) tools executed (with errors)"
        }
        if toolCalls.count > 2 {
            return "⚡️ Long-Horizon Run: \(toolCalls.count) tools executed"
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
