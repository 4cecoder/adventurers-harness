// CompactGateBar.swift
// Adventurers Harness — Top Certification Gate Progress Bar & Workspace Scope Selector

import SwiftUI
import AdventurersCore

struct CompactGateBar: View {
    @ObservedObject var state: GatePipelineState
    @Binding var isExpanded: Bool
    var workingDirectoryName: String = "workspace"
    var workingDirectory: String = ""
    var onChooseDirectory: (() -> Void)? = nil

    init(
        state: GatePipelineState,
        isExpanded: Binding<Bool>,
        workingDirectoryName: String = "workspace",
        workingDirectory: String = "",
        onChooseDirectory: (() -> Void)? = nil
    ) {
        self._state = ObservedObject(wrappedValue: state)
        self._isExpanded = isExpanded
        self.workingDirectoryName = workingDirectoryName
        self.workingDirectory = workingDirectory
        self.onChooseDirectory = onChooseDirectory
    }

    public var body: some View {
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
