// TaskContractProgressCard.swift
// Adventurers Harness — Interactive Task Contract & Long-Horizon Progress Banner

import SwiftUI
import AdventurersCore

public struct TaskContractProgressCard: View {
    public let contract: LongHorizonTaskContract
    public let onRollback: () -> Void

    public init(contract: LongHorizonTaskContract, onRollback: @escaping () -> Void) {
        self.contract = contract
        self.onRollback = onRollback
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: contract.currentPhase.icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(phaseColor)

                Text(contract.currentPhase.rawValue)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.adTextPrimary)

                Spacer()

                Text("\(Int(contract.progressFraction * 100))%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(phaseColor)

                if contract.checkpointsSaved > 0 {
                    Button(action: onRollback) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 9, weight: .bold))
                            Text("Rollback")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.adElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .foregroundStyle(Color.adTextSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Revert to pre-execution checkpoint")
                }
            }

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
                Text(contract.goal)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.adTextSecondary)
                    .lineLimit(1)

                Spacer()

                Text("Checkpoints: \(contract.checkpointsSaved)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.adTextTertiary)
            }
        }
        .padding(10)
        .background(Color.adCard.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(phaseColor.opacity(0.25), lineWidth: 1)
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
