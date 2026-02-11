import PRRadarConfigService
import SwiftUI

enum NavigationPhase: CaseIterable, Identifiable {
    var id: Self { self }
    case summary
    case diff
    case report

    var displayName: String {
        switch self {
        case .summary: "Summary"
        case .diff: "Diff"
        case .report: "Report"
        }
    }

    var primaryPhase: PRRadarPhase {
        switch self {
        case .summary: .sync
        case .diff: .sync
        case .report: .report
        }
    }

    var representedPhases: [PRRadarPhase] {
        switch self {
        case .summary: []
        case .diff: [.sync, .prepare, .analyze]
        case .report: [.report]
        }
    }
}

struct PipelineStatusView: View {

    let prModel: PRModel
    @Binding var selectedNavPhase: NavigationPhase
    @State private var showingErrorPhase: NavigationPhase?

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
        let state = combinedState(navPhase)
        Button {
            selectedNavPhase = navPhase
            if case .failed = state {
                showingErrorPhase = navPhase
            }
        } label: {
            HStack(spacing: 4) {
                statusIndicator(for: state)
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
        .accessibilityIdentifier("phaseButton_\(navPhase.displayName.lowercased())")
        .buttonStyle(.plain)
        .popover(item: errorPopoverItem(for: navPhase), arrowEdge: .top) { phase in
            errorPopoverContent(for: phase)
        }
    }

    private func errorPopoverItem(for navPhase: NavigationPhase) -> Binding<NavigationPhase?> {
        Binding {
            showingErrorPhase == navPhase ? showingErrorPhase : nil
        } set: {
            showingErrorPhase = $0
        }
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
        case .refreshing:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption2)
                .foregroundStyle(.blue)
                .symbolEffect(.rotate)
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

    @ViewBuilder
    private func errorPopoverContent(for navPhase: NavigationPhase) -> some View {
        let errors = failedPhaseErrors(for: navPhase)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(errors, id: \.phase) { entry in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.phase.displayName)
                            .font(.caption.bold())
                        if !entry.error.isEmpty {
                            Text(entry.error)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func failedPhaseErrors(for navPhase: NavigationPhase) -> [(phase: PRRadarPhase, error: String)] {
        navPhase.representedPhases.compactMap { phase in
            if case .failed(let error, _) = prModel.stateFor(phase) {
                return (phase: phase, error: error)
            }
            return nil
        }
    }

    private func combinedState(_ navPhase: NavigationPhase) -> PRModel.PhaseState {
        let phases = navPhase.representedPhases
        if phases.isEmpty {
            return .completed(logs: "")
        }

        let states = phases.map { prModel.stateFor($0) }

        let hasRunning = states.contains(where: { if case .running = $0 { return true } else { return false } })
        let hasRefreshing = states.contains(where: { if case .refreshing = $0 { return true } else { return false } })

        if hasRunning {
            return .running(logs: "")
        }
        if hasRefreshing {
            return .refreshing(logs: "")
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
