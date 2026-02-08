import PRRadarConfigService
import PRRadarModels
import PRReviewFeature
import SwiftUI

struct ReviewDetailView: View {

    @Environment(ReviewModel.self) private var reviewModel
    @State private var showEffectiveDiff = false

    var body: some View {
        VStack(spacing: 0) {
            PipelineStatusView()

            Divider()

            PhaseInputView(phase: reviewModel.selectedPhase)
                .padding()

            Divider()

            phaseOutputView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Run All") {
                    Task { await reviewModel.runAllPhases() }
                }
                .disabled(reviewModel.isAnyPhaseRunning || reviewModel.prNumber.isEmpty)
            }
        }
    }

    // MARK: - Phase Output Views

    @ViewBuilder
    private var phaseOutputView: some View {
        switch reviewModel.selectedPhase {
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
        if let fullDiff = reviewModel.diff?.fullDiff {
            VStack(spacing: 0) {
                if reviewModel.diff?.effectiveDiff != nil {
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
                    effectiveDiff: reviewModel.diff?.effectiveDiff
                )
            }
            .sheet(isPresented: $showEffectiveDiff) {
                if let effectiveDiff = reviewModel.diff?.effectiveDiff {
                    EffectiveDiffView(
                        fullDiff: fullDiff,
                        effectiveDiff: effectiveDiff,
                        moveReport: reviewModel.diff?.moveReport
                    )
                    .frame(minWidth: 900, minHeight: 600)
                }
            }
        } else if let files = reviewModel.diff?.files {
            List(files, id: \.self) { file in
                Text(file)
                    .font(.system(.body, design: .monospaced))
            }
        } else if case .running(let logs) = reviewModel.stateFor(.pullRequest) {
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
        if let output = reviewModel.rules {
            RulesPhaseView(
                focusAreas: output.focusAreas,
                rules: output.rules,
                tasks: output.tasks
            )
        } else if case .running(let logs) = reviewModel.stateFor(reviewModel.selectedPhase) {
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
        if let output = reviewModel.evaluation {
            EvaluationsPhaseView(
                diff: reviewModel.diff?.fullDiff,
                evaluations: output.evaluations,
                summary: output.summary
            )
        } else if case .running(let logs) = reviewModel.stateFor(.evaluations) {
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
        if let output = reviewModel.report {
            ReportPhaseView(
                report: output.report,
                markdownContent: output.markdownContent
            )
        } else if case .running(let logs) = reviewModel.stateFor(.report) {
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
