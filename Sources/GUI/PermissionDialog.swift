// PermissionDialog.swift
// Adventurers Harness — Simplified permission dialog

import SwiftUI
import AdventurersCore

// MARK: - Models

struct PermissionRequest: Identifiable, Sendable {
    let id = UUID()
    let toolName: String
    let riskLevel: RiskLevel
    let command: String
    let agentID: String
    let timestamp: Date
}

enum PermissionDecision: Sendable {
    case allowOnce, allowForSession, deny
}

struct PermissionRecord: Identifiable, Sendable {
    let id = UUID()
    let request: PermissionRequest
    let decision: PermissionDecision
    let timestamp: Date
}

// MARK: - Permission Dialog View

struct PermissionDialogView: View {
    let request: PermissionRequest
    let onDecision: (PermissionDecision) -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: riskIcon)
                    .foregroundStyle(riskColor)
                Text(request.toolName)
                    .font(.headline)
                Spacer()
                BadgeView(text: request.riskLevel.rawValue, color: riskColor, size: .small)
            }

            Text(request.command)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 12) {
                Button("Deny") { onDecision(.deny) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Allow for Session") { onDecision(.allowForSession) }
                Button("Allow Once") { onDecision(.allowOnce) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 450)
    }

    private var riskIcon: String {
        switch request.riskLevel {
        case .readOnly: return "eye"
        case .network: return "network"
        case .write: return "pencil"
        case .execute: return "terminal"
        case .destructive: return "exclamationmark.triangle.fill"
        }
    }

    private var riskColor: Color {
        switch request.riskLevel {
        case .readOnly: return .blue
        case .network: return .yellow
        case .write: return .orange
        case .execute: return .red
        case .destructive: return .red
        }
    }
}
