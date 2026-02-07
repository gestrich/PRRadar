import PRRadarConfigService
import SwiftUI

struct PipelineStatusView: View {

    @Environment(PRReviewModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(PRRadarPhase.allCases.enumerated()), id: \.element) { index, phase in
                if index > 0 {
                    arrow
                }
                phaseNode(phase)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private func phaseNode(_ phase: PRRadarPhase) -> some View {
        Button {
            model.selectedPhase = phase
        } label: {
            HStack(spacing: 4) {
                statusIndicator(for: model.stateFor(phase))
                Text(shortName(for: phase))
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                model.selectedPhase == phase
                    ? Color.accentColor.opacity(0.15)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var arrow: some View {
        Image(systemName: "chevron.right")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 2)
    }

    @ViewBuilder
    private func statusIndicator(for state: PRReviewModel.PhaseState) -> some View {
        switch state {
        case .idle:
            Circle()
                .fill(.gray.opacity(0.4))
                .frame(width: 8, height: 8)
        case .running:
            ProgressView()
                .controlSize(.mini)
                .frame(width: 8, height: 8)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }

    private func shortName(for phase: PRRadarPhase) -> String {
        switch phase {
        case .pullRequest: "Diff"
        case .focusAreas: "Focus"
        case .rules: "Rules"
        case .tasks: "Tasks"
        case .evaluations: "Evaluate"
        case .report: "Report"
        }
    }
}
