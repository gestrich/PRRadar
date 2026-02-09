import PRRadarConfigService
import SwiftUI

enum NavigationPhase: CaseIterable {
    case summary
    case diff
    case rules
    case report

    var displayName: String {
        switch self {
        case .summary: "Summary"
        case .diff: "Diff"
        case .rules: "Rules"
        case .report: "Report"
        }
    }

    var primaryPhase: PRRadarPhase {
        switch self {
        case .summary: .pullRequest
        case .diff: .pullRequest
        case .rules: .rules
        case .report: .report
        }
    }

    var representedPhases: [PRRadarPhase] {
        switch self {
        case .summary: []
        case .diff: [.pullRequest, .evaluations]
        case .rules: [.focusAreas, .rules, .tasks]
        case .report: [.report]
        }
    }
}

struct PipelineStatusView: View {

    let prModel: PRModel
    @Binding var selectedNavPhase: NavigationPhase

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(NavigationPhase.allCases.enumerated()), id: \.element) { index, navPhase in
                if index > 0 {
                    arrow
                }
                phaseNode(navPhase)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private func phaseNode(_ navPhase: NavigationPhase) -> some View {
        Button {
            selectedNavPhase = navPhase
        } label: {
            HStack(spacing: 4) {
                statusIndicator(for: combinedState(navPhase))
                Text(navPhase.displayName)
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                selectedNavPhase == navPhase
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
    private func statusIndicator(for state: PRModel.PhaseState) -> some View {
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

    private func combinedState(_ navPhase: NavigationPhase) -> PRModel.PhaseState {
        let phases = navPhase.representedPhases
        if phases.isEmpty {
            return .completed(logs: "")
        }

        let states = phases.map { prModel.stateFor($0) }

        if states.contains(where: { if case .running = $0 { return true } else { return false } }) {
            return .running(logs: "")
        }
        if states.contains(where: { if case .failed = $0 { return true } else { return false } }) {
            return .failed(error: "", logs: "")
        }
        if states.allSatisfy({ if case .completed = $0 { return true } else { return false } }) {
            return .completed(logs: "")
        }
        return .idle
    }
}
