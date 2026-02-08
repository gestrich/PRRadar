import PRRadarConfigService
import SwiftUI

struct PhaseInputView: View {

    @Environment(ReviewModel.self) private var reviewModel
    let phase: PRRadarPhase

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(phaseTitle)
                    .font(.headline)
                Spacer()
                runButton
            }

            phaseDescription
                .font(.subheadline)
                .foregroundStyle(.secondary)

            configInfo(reviewModel.repoConfig)

            stateView
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Run Button

    @ViewBuilder
    private var runButton: some View {
        let state = reviewModel.stateFor(phase)
        let isRunning = { if case .running = state { return true } else { return false } }()

        HStack(spacing: 8) {
            if isRunning {
                ProgressView()
                    .controlSize(.small)
            }

            Button(isRunning ? "Running..." : "Run") {
                Task { await reviewModel.runPhase(phase) }
            }
            .disabled(!reviewModel.canRunPhase(phase))
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    // MARK: - Phase Info

    private var phaseTitle: String {
        switch phase {
        case .pullRequest: "Fetch PR Diff"
        case .focusAreas, .rules, .tasks: "Rules & Tasks"
        case .evaluations: "Run Evaluations"
        case .report: "Generate Report"
        }
    }

    @ViewBuilder
    private var phaseDescription: some View {
        switch phase {
        case .pullRequest:
            Text("Fetches the PR diff and parses it into structured data.")
        case .focusAreas, .rules, .tasks:
            Text("Generates focus areas, loads rules, and creates evaluation tasks.")
        case .evaluations:
            Text("Runs Claude evaluations for each task.")
        case .report:
            Text("Generates a summary report of all evaluation results.")
        }
    }

    @ViewBuilder
    private func configInfo(_ config: RepoConfiguration) -> some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Text("Repo:")
                    .foregroundStyle(.secondary)
                Text(URL(fileURLWithPath: config.repoPath).lastPathComponent)
            }
            .font(.caption)

            if !config.rulesDir.isEmpty, showsRulesDir {
                HStack(spacing: 4) {
                    Text("Rules:")
                        .foregroundStyle(.secondary)
                    Text(URL(fileURLWithPath: config.rulesDir).lastPathComponent)
                }
                .font(.caption)
            }
        }
    }

    private var showsRulesDir: Bool {
        switch phase {
        case .focusAreas, .rules, .tasks: true
        default: false
        }
    }

    // MARK: - State View

    @ViewBuilder
    private var stateView: some View {
        switch reviewModel.stateFor(phase) {
        case .idle:
            if !reviewModel.canRunPhase(phase) && !reviewModel.prNumber.isEmpty {
                Text("Prerequisite phases must complete first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .running(let logs):
            if !logs.isEmpty {
                logsView(logs)
            }
        case .completed(let logs):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Completed")
                    .foregroundStyle(.green)
            }
            .font(.caption)
            if !logs.isEmpty {
                logsView(logs)
            }
        case .failed(let error, let logs):
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
            if !logs.isEmpty {
                logsView(logs)
            }
        }
    }

    @ViewBuilder
    private func logsView(_ logs: String) -> some View {
        DisclosureGroup("Logs") {
            ScrollView {
                Text(logs)
                    .font(.system(.caption2, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 120)
        }
        .font(.caption)
    }
}
