import PRRadarConfigService
import SwiftUI

struct PhaseInputView: View {

    let prModel: PRModel
    let phase: PRRadarPhase
    var secondaryPhase: PRRadarPhase? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(phaseTitle)
                    .font(.headline)
                Spacer()
                runButton(for: phase)
            }

            phaseDescription
                .font(.subheadline)
                .foregroundStyle(.secondary)

            configInfo(prModel.config)

            stateView(for: phase)

            if let secondary = secondaryPhase {
                Divider()

                HStack {
                    Text(phaseTitle(for: secondary))
                        .font(.headline)
                    Spacer()
                    runButton(for: secondary)
                }

                phaseDescription(for: secondary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                stateView(for: secondary)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Run Button

    @ViewBuilder
    private func runButton(for targetPhase: PRRadarPhase) -> some View {
        let state = prModel.stateFor(targetPhase)
        let isRunning: Bool = {
            switch state {
            case .running, .refreshing: return true
            default: return false
            }
        }()
        let buttonLabel: String = {
            switch state {
            case .refreshing: return "Refreshing..."
            case .running: return "Running..."
            default: return "Run"
            }
        }()

        HStack(spacing: 8) {
            if isRunning {
                ProgressView()
                    .controlSize(.small)
            }

            Button(buttonLabel) {
                Task { await prModel.runPhase(targetPhase) }
            }
            .disabled(!prModel.canRunPhase(targetPhase))
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    // MARK: - Phase Info

    private var phaseTitle: String {
        phaseTitle(for: phase)
    }

    private func phaseTitle(for targetPhase: PRRadarPhase) -> String {
        switch targetPhase {
        case .metadata: "Metadata"
        case .diff: "Sync PR"
        case .prepare: "Prepare"
        case .analyze: "Analyze"
        case .report: "Generate Report"
        }
    }

    @ViewBuilder
    private var phaseDescription: some View {
        phaseDescription(for: phase)
    }

    @ViewBuilder
    private func phaseDescription(for targetPhase: PRRadarPhase) -> some View {
        switch targetPhase {
        case .metadata:
            Text("Fetches PR metadata, comments, and repository info.")
        case .diff:
            Text("Fetches PR data including diff, metadata, comments, and reviews.")
        case .prepare:
            Text("Generates focus areas, loads rules, and creates evaluation tasks.")
        case .analyze:
            Text("Runs Claude evaluations for each task.")
        case .report:
            Text("Generates a summary report of all evaluation results.")
        }
    }

    @ViewBuilder
    private func configInfo(_ config: RepositoryConfiguration) -> some View {
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
        case .prepare: true
        default: false
        }
    }

    // MARK: - State View

    @ViewBuilder
    private func stateView(for targetPhase: PRRadarPhase) -> some View {
        switch prModel.stateFor(targetPhase) {
        case .idle:
            if !prModel.canRunPhase(targetPhase) && !prModel.prNumber.isEmpty {
                Text("Prerequisite phases must complete first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .running(let logs), .refreshing(let logs):
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
