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
                    postedComments: prModel.postedComments?.comments ?? [],
                    imageURLMap: prModel.imageURLMap.isEmpty ? nil : prModel.imageURLMap,
                    imageBaseDir: prModel.imageBaseDir
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .diff, .report:
                PhaseInputView(
                    prModel: prModel,
                    phase: selectedNavPhase.primaryPhase,
                    secondaryPhase: selectedNavPhase == .diff ? .rules : nil
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
                    postedReviewComments: prModel.postedComments?.reviewComments ?? [],
                    tasks: prModel.rules?.tasks ?? []
                )
            }
            .overlay(alignment: .top) {
                if case .refreshing = prModel.stateFor(.pullRequest) {
                    refreshingBanner
                }
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
            .overlay(alignment: .top) {
                if case .refreshing = prModel.stateFor(.pullRequest) {
                    refreshingBanner
                }
            }
        } else if case .running = prModel.stateFor(.pullRequest) {
            loadingView("Fetching PR diff...")
        } else if case .refreshing = prModel.stateFor(.pullRequest) {
            loadingView("Refreshing PR diff...")
        } else {
            ContentUnavailableView(
                "No Diff Data",
                systemImage: "doc.text",
                description: Text("Run Phase 1 to fetch the PR diff.")
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
        } else if case .running = prModel.stateFor(.report) {
            loadingView("Generating report...")
        } else if case .refreshing = prModel.stateFor(.report) {
            loadingView("Generating report...")
        } else {
            ContentUnavailableView(
                "No Report Data",
                systemImage: "chart.bar.doc.horizontal",
                description: Text("Run Phase 6 to generate the report.")
            )
        }
    }

    // MARK: - Loading Indicators

    @ViewBuilder
    private func loadingView(_ message: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var refreshingBanner: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.mini)
            Text("Updating...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.bar)
        .clipShape(Capsule())
        .shadow(radius: 2)
        .padding(.top, 8)
    }
}
