// TaskContractProgressCard.swift
// Adventurers Harness — Interactive Task Contract & Long-Horizon Progress Banner

import SwiftUI
import AdventurersCore

public struct TaskContractProgressCard: View {
    public let contract: LongHorizonTaskContract
    public let onRollback: () -> Void

    @State private var isExpanded: Bool = false // Collapsed by default

    public init(contract: LongHorizonTaskContract, onRollback: @escaping () -> Void) {
        self.contract = contract
        self.onRollback = onRollback
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Collapsed / Summary Header (Always Visible, Compact & Fast)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.adTextTertiary)
                        .frame(width: 12)

                    Image(systemName: contract.currentPhase.icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(phaseColor)

                    Text(contract.currentPhase.rawValue)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.adTextPrimary)

                    Text("•")
                        .foregroundStyle(Color.adTextTertiary)

                    Text(contract.goal)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.adTextSecondary)
                        .lineLimit(1)

                    Spacer()

                    Text("\(Int(contract.progressFraction * 100))%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(phaseColor)

                    if contract.checkpointsSaved > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 9))
                            Text("\(contract.checkpointsSaved)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                        }
                        .foregroundStyle(Color.adTextTertiary)
                    }
                }
            }
            .buttonStyle(.plain)

            // Expanded Long-Horizon Details View
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .foregroundStyle(Color.adDivider)

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.adElevated)
                                .frame(height: 5)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(phaseColor)
                                .frame(width: max(4, geo.size.width * CGFloat(contract.progressFraction)), height: 5)
                        }
                    }
                    .frame(height: 5)

                    HStack {
                        Text("Turn Budget: \(contract.turnBudget) turns max")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.adTextTertiary)

                        Spacer()

                        if contract.checkpointsSaved > 0 {
                            Button(action: onRollback) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.uturn.backward")
                                        .font(.system(size: 9, weight: .bold))
                                    Text("Rollback Checkpoint")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.adElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .foregroundStyle(Color.adOrange)
                            }
                            .buttonStyle(.plain)
                            .help("Revert to pre-execution checkpoint")
                        }
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(8)
        .background(Color.adCard.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(phaseColor.opacity(0.2), lineWidth: 1)
        )
    }

    private var phaseColor: Color {
        switch contract.currentPhase {
        case .planning: return Color.adInfo
        case .execution: return Color.adOrange
        case .verification: return Color.adSuccess
        case .completed: return Color.adSuccess
        case .rolledBack: return Color.adWarning
        }
    }
}
