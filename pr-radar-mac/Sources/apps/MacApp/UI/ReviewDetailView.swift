import PRRadarConfigService
import PRRadarModels
import PRReviewFeature
import SwiftUI

struct ReviewDetailView: View {

    let prModel: PRModel
    @State private var showEffectiveDiff = false

    var body: some View {
        VStack(spacing: 0) {
            PipelineStatusView(prModel: prModel)

            Divider()

            PhaseInputView(prModel: prModel, phase: prModel.selectedPhase)
                .padding()

            Divider()

            phaseOutputView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Run All") {
                    Task { await prModel.runAllPhases() }
                }
                .disabled(prModel.isAnyPhaseRunning || prModel.prNumber.isEmpty)
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    let path = "\(prModel.config.absoluteOutputDir)/\(prModel.prNumber)"
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                } label: {
                    Image(systemName: "folder")
                }
                .help("Open PR data in Finder")
                .disabled(prModel.prNumber.isEmpty)
            }
        }
    }

    // MARK: - Phase Output Views

    @ViewBuilder
    private var phaseOutputView: some View {
        switch prModel.selectedPhase {
        case .pullRequest:
            diffOutputView
        case .focusAreas, .rules, .tasks:
            rulesOutputView
        case .evaluations:
            evaluationsOutputView
        case .report:
            reportOutputView
        }
    }

    @ViewBuilder
    private var diffOutputView: some View {
        if let fullDiff = prModel.diff?.fullDiff {
            VStack(spacing: 0) {
                if prModel.diff?.effectiveDiff != nil {
                    HStack {
                        Spacer()
                        Button {
                            showEffectiveDiff = true
                        } label: {
                            Label("View Effective Diff", systemImage: "doc.text.magnifyingglass")
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    Divider()
                }

                DiffPhaseView(
                    fullDiff: fullDiff,
                    effectiveDiff: prModel.diff?.effectiveDiff
                )
            }
            .sheet(isPresented: $showEffectiveDiff) {
                if let effectiveDiff = prModel.diff?.effectiveDiff {
                    EffectiveDiffView(
                        fullDiff: fullDiff,
                        effectiveDiff: effectiveDiff,
                        moveReport: prModel.diff?.moveReport
                    )
                    .frame(minWidth: 900, minHeight: 600)
                }
            }
        } else if let files = prModel.diff?.files {
            List(files, id: \.self) { file in
                Text(file)
                    .font(.system(.body, design: .monospaced))
            }
        } else if case .running(let logs) = prModel.stateFor(.pullRequest) {
            runningLogView(logs)
        } else {
            ContentUnavailableView(
                "No Diff Data",
                systemImage: "doc.text",
                description: Text("Run Phase 1 to fetch the PR diff.")
            )
        }
    }

    @ViewBuilder
    private var rulesOutputView: some View {
        if let output = prModel.rules {
            RulesPhaseView(
                focusAreas: output.focusAreas,
                rules: output.rules,
                tasks: output.tasks
            )
        } else if case .running(let logs) = prModel.stateFor(prModel.selectedPhase) {
            runningLogView(logs)
        } else {
            ContentUnavailableView(
                "No Rules Data",
                systemImage: "list.clipboard",
                description: Text("Run Phases 2-4 to generate focus areas, rules, and tasks.")
            )
        }
    }

    @ViewBuilder
    private var evaluationsOutputView: some View {
        if let output = prModel.evaluation {
            EvaluationsPhaseView(
                diff: prModel.diff?.fullDiff,
                comments: output.comments,
                summary: output.summary,
                prModel: prModel
            )
        } else if case .running(let logs) = prModel.stateFor(.evaluations) {
            runningLogView(logs)
        } else {
            ContentUnavailableView(
                "No Evaluation Data",
                systemImage: "brain",
                description: Text("Run the evaluations phase first.")
            )
        }
    }

    @ViewBuilder
    private var reportOutputView: some View {
        if let output = prModel.report {
            ReportPhaseView(
                report: output.report,
                markdownContent: output.markdownContent
            )
        } else if case .running(let logs) = prModel.stateFor(.report) {
            runningLogView(logs)
        } else {
            ContentUnavailableView(
                "No Report Data",
                systemImage: "chart.bar.doc.horizontal",
                description: Text("Run Phase 6 to generate the report.")
            )
        }
    }

    // MARK: - Running Log

    @ViewBuilder
    private func runningLogView(_ logs: String) -> some View {
        ScrollView {
            ScrollViewReader { proxy in
                Text(logs.isEmpty ? "Running..." : logs)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .id("logBottom")
                    .onChange(of: logs) {
                        proxy.scrollTo("logBottom", anchor: .bottom)
                    }
            }
        }
    }
}
