import PRRadarConfigService
import PRRadarModels
import PRReviewFeature
import SwiftUI

struct ReviewDetailView: View {

    let prModel: PRModel
    @State private var selectedNavPhase: NavigationPhase = .summary
    @State private var showEffectiveDiff = false

    var body: some View {
        VStack(spacing: 0) {
            prHeader

            PipelineStatusView(prModel: prModel, selectedNavPhase: $selectedNavPhase)

            Divider()

            switch selectedNavPhase {
            case .summary:
                SummaryPhaseView(
                    metadata: prModel.metadata,
                    postedComments: prModel.postedComments?.comments ?? []
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .diff, .rules, .report:
                PhaseInputView(
                    prModel: prModel,
                    phase: selectedNavPhase.primaryPhase,
                    secondaryPhase: selectedNavPhase == .diff ? .evaluations : nil
                )
                    .padding()

                Divider()

                phaseOutputView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: selectedNavPhase) {
            if selectedNavPhase != .summary {
                prModel.selectedPhase = selectedNavPhase.primaryPhase
            }
        }
    }

    // MARK: - PR Header

    @ViewBuilder
    private var prHeader: some View {
        let pr = prModel.metadata
        if !pr.title.isEmpty || !pr.author.login.isEmpty {
            HStack(spacing: 8) {
                Text("#\(pr.number)")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text(pr.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                if !pr.author.login.isEmpty {
                    Text(pr.author.name.isEmpty ? pr.author.login : pr.author.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)

            Divider()
        }
    }

    // MARK: - Phase Output Views

    @ViewBuilder
    private var phaseOutputView: some View {
        switch selectedNavPhase {
        case .summary:
            EmptyView()
        case .diff:
            diffOutputView
        case .rules:
            rulesOutputView
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
                    effectiveDiff: prModel.diff?.effectiveDiff,
                    comments: prModel.evaluation?.comments,
                    evaluationSummary: prModel.evaluation?.summary,
                    prModel: prModel,
                    postedReviewComments: prModel.postedComments?.reviewComments ?? []
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
