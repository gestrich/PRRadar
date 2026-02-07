import PRRadarConfigService
import PRRadarModels
import PRReviewFeature
import SwiftUI

struct ReviewDetailView: View {

    let config: RepoConfiguration
    let review: ReviewState

    @Environment(PRReviewModel.self) private var model
    @State private var showEffectiveDiff = false
    @State private var showCommentApproval = false

    var body: some View {
        VStack(spacing: 0) {
            PipelineStatusView()
                .environment(model)

            Divider()

            PhaseInputView(phase: review.selectedPhase)
                .environment(model)
                .padding()

            Divider()

            phaseOutputView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Run All") {
                    Task { await model.runAllPhases() }
                }
                .disabled(model.isAnyPhaseRunning || model.prNumber.isEmpty)
            }
        }
    }

    // MARK: - Phase Output Views

    @ViewBuilder
    private var phaseOutputView: some View {
        switch review.selectedPhase {
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
        if let fullDiff = review.diff?.fullDiff {
            VStack(spacing: 0) {
                if review.diff?.effectiveDiff != nil {
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
                    effectiveDiff: review.diff?.effectiveDiff
                )
            }
            .sheet(isPresented: $showEffectiveDiff) {
                if let effectiveDiff = review.diff?.effectiveDiff {
                    EffectiveDiffView(
                        fullDiff: fullDiff,
                        effectiveDiff: effectiveDiff,
                        moveReport: review.diff?.moveReport
                    )
                    .frame(minWidth: 900, minHeight: 600)
                }
            }
        } else if let files = review.diff?.files {
            List(files, id: \.self) { file in
                Text(file)
                    .font(.system(.body, design: .monospaced))
            }
        } else if case .running(let logs) = model.stateFor(.pullRequest) {
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
        if let output = review.rules {
            RulesPhaseView(
                focusAreas: output.focusAreas,
                rules: output.rules,
                tasks: output.tasks
            )
        } else if case .running(let logs) = model.stateFor(review.selectedPhase) {
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
        if let output = review.evaluation {
            VStack(spacing: 0) {
                let hasViolations = output.evaluations.contains { $0.evaluation.violatesRule }
                if hasViolations {
                    HStack {
                        Spacer()
                        Button {
                            showCommentApproval = true
                        } label: {
                            Label("Review & Approve Comments", systemImage: "text.bubble")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    Divider()
                }

                EvaluationsPhaseView(
                    evaluations: output.evaluations,
                    summary: output.summary
                )
            }
            .sheet(isPresented: $showCommentApproval) {
                CommentApprovalView(
                    evaluations: output.evaluations,
                    posted: review.comments?.posted ?? false,
                    onPost: { dryRun in
                        Task { await model.runComments(dryRun: dryRun) }
                    }
                )
                .environment(model)
                .frame(minWidth: 900, minHeight: 600)
            }
        } else if case .running(let logs) = model.stateFor(.evaluations) {
            runningLogView(logs)
        } else {
            ContentUnavailableView(
                "No Evaluation Data",
                systemImage: "brain",
                description: Text("Run Phase 5 to evaluate the code.")
            )
        }
    }

    @ViewBuilder
    private var reportOutputView: some View {
        if let output = review.report {
            ReportPhaseView(
                report: output.report,
                markdownContent: output.markdownContent
            )
        } else if case .running(let logs) = model.stateFor(.report) {
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
