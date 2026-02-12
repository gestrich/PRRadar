import PRRadarConfigService
import PRRadarModels
import PRReviewFeature
import SwiftUI

struct ReviewDetailView: View {

    let prModel: PRModel
    @State private var selectedNavPhase: NavigationPhase = .summary
    @State private var showEffectiveDiff = false
    @State private var showAIOutput = false

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
            case .diff:
                diffToolbar

                Divider()

                phaseOutputView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .report:
                PhaseInputView(
                    prModel: prModel,
                    phase: selectedNavPhase.primaryPhase
                )
                    .padding()

                Divider()

                phaseOutputView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - PR Header

    @ViewBuilder
    private var prHeader: some View {
        let pr = prModel.metadata
        if !pr.title.isEmpty || !pr.author.login.isEmpty {
            HStack(spacing: 8) {
                Text(pr.displayNumber)
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
        if let fullDiff = prModel.syncSnapshot?.fullDiff {
            VStack(spacing: 0) {
                if hasAIOutput || prModel.syncSnapshot?.effectiveDiff != nil {
                    HStack {
                        if hasAIOutput {
                            Button {
                                showAIOutput = true
                            } label: {
                                HStack(spacing: 4) {
                                    if prModel.isAIPhaseRunning {
                                        ProgressView()
                                            .controlSize(.mini)
                                    }
                                    Label("AI Output", systemImage: "text.bubble")
                                }
                            }
                            .accessibilityIdentifier("aiOutputButton")
                        }
                        Spacer()
                        if prModel.syncSnapshot?.effectiveDiff != nil {
                            Button {
                                showEffectiveDiff = true
                            } label: {
                                Label("View Effective Diff", systemImage: "doc.text.magnifyingglass")
                            }
                            .accessibilityIdentifier("effectiveDiffButton")
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    Divider()
                }

                DiffPhaseView(
                    fullDiff: fullDiff,
                    prModel: prModel
                )
            }
            .overlay(alignment: .top) {
                if case .refreshing = prModel.stateFor(.diff) {
                    refreshingBanner
                }
            }
            .sheet(isPresented: $showEffectiveDiff) {
                if let effectiveDiff = prModel.syncSnapshot?.effectiveDiff {
                    EffectiveDiffView(
                        fullDiff: fullDiff,
                        effectiveDiff: effectiveDiff,
                        moveReport: prModel.syncSnapshot?.moveReport
                    )
                    .frame(minWidth: 900, minHeight: 600)
                }
            }
            .sheet(isPresented: $showAIOutput) {
                aiOutputView
                    .frame(minWidth: 800, minHeight: 500)
            }
        } else if let files = prModel.syncSnapshot?.files {
            List(files, id: \.self) { file in
                Text(file)
                    .font(.system(.body, design: .monospaced))
            }
            .overlay(alignment: .top) {
                if case .refreshing = prModel.stateFor(.diff) {
                    refreshingBanner
                }
            }
        } else if case .running = prModel.stateFor(.diff) {
            loadingView("Fetching PR diff...")
        } else if case .refreshing = prModel.stateFor(.diff) {
            loadingView("Refreshing PR diff...")
        } else {
            ContentUnavailableView(
                "No Diff Data",
                systemImage: "doc.text",
                description: Text("Run Sync to fetch PR data.")
            )
        }
    }

    private var hasAIOutput: Bool {
        prModel.isAIPhaseRunning || !prModel.savedTranscripts.isEmpty || !prModel.liveTranscripts.isEmpty
    }

    @ViewBuilder
    private var aiOutputView: some View {
        if prModel.isAIPhaseRunning {
            AITranscriptView(transcriptsByPhase: prModel.liveTranscripts, isStreaming: true)
        } else if !prModel.savedTranscripts.isEmpty {
            AITranscriptView(transcriptsByPhase: prModel.savedTranscripts)
        } else if !prModel.liveTranscripts.isEmpty {
            AITranscriptView(transcriptsByPhase: prModel.liveTranscripts)
        } else {
            ContentUnavailableView(
                "No AI Output",
                systemImage: "text.bubble",
                description: Text("Run Focus Areas or Evaluations to see AI output.")
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
                description: Text("Run Report to generate the report.")
            )
        }
    }

    // MARK: - Diff Toolbar

    @ViewBuilder
    private var diffToolbar: some View {
        HStack(spacing: 12) {
            compactPhaseButton(phase: .diff, label: "Sync PR", icon: "arrow.down.doc")
                .accessibilityIdentifier("syncButton")
            compactPhaseButton(phase: .prepare, label: "Prepare", icon: "list.bullet.clipboard")
                .accessibilityIdentifier("prepareButton")
            compactPhaseButton(phase: .analyze, label: "Analyze", icon: "checkmark.shield")
                .accessibilityIdentifier("analyzeButton")
            Spacer()
            commitPicker
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var commitPicker: some View {
        let commits = prModel.availableCommits
        if commits.count > 1, let current = prModel.currentCommitHash {
            Picker("Commit", selection: Binding(
                get: { current },
                set: { prModel.switchToCommit($0) }
            )) {
                ForEach(commits, id: \.self) { commit in
                    Text(commit).tag(commit)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityIdentifier("commitPicker")
        } else if let current = prModel.currentCommitHash {
            Text(current)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func compactPhaseButton(phase: PRRadarPhase, label: String, icon: String) -> some View {
        let state = prModel.stateFor(phase)
        let isRunning: Bool = {
            switch state {
            case .running, .refreshing: return true
            default: return false
            }
        }()
        let isCompleted: Bool = {
            if case .completed = state { return true }
            return false
        }()

        Button {
            Task { await prModel.runPhase(phase) }
        } label: {
            HStack(spacing: 4) {
                if isRunning {
                    ProgressView()
                        .controlSize(.mini)
                } else if isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Label(label, systemImage: icon)
            }
        }
        .disabled(!prModel.canRunPhase(phase))
        .controlSize(.small)
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
