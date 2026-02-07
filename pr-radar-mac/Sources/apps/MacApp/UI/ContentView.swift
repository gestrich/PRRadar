import PRRadarConfigService
import SwiftUI

struct ContentView: View {

    @Environment(PRReviewModel.self) private var model
    @State private var showSettings = false
    @State private var showEffectiveDiff = false
    @State private var showCommentApproval = false

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            configSidebar
        } content: {
            prListView
        } detail: {
            phaseDetailView
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(model)
        }
    }

    // MARK: - Column 1: Config Sidebar

    @ViewBuilder
    private var configSidebar: some View {
        @Bindable var model = model

        let configBinding = Binding<RepoConfiguration?>(
            get: { model.selectedConfiguration },
            set: { newConfig in
                if let config = newConfig {
                    model.selectConfiguration(config)
                }
            }
        )

        List(model.settings.configurations, selection: configBinding) { config in
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(config.name)
                        .font(.body)
                    if config.isDefault {
                        Text("Default")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }
                Text(URL(fileURLWithPath: config.repoPath).lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .tag(config)
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 150, ideal: 180)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gear")
                }
                .help("Manage configurations")
            }
        }
    }

    // MARK: - Column 2: PR List

    @ViewBuilder
    private var prListView: some View {
        @Bindable var model = model

        Group {
            if model.selectedConfiguration == nil {
                ContentUnavailableView(
                    "Select a Configuration",
                    systemImage: "folder",
                    description: Text("Choose a repo configuration from the sidebar.")
                )
            } else if model.discoveredPRs.isEmpty {
                ContentUnavailableView(
                    "No Reviews Found",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("No PR review data found in the output directory.")
                )
            } else {
                List(model.discoveredPRs, selection: $model.selectedPR) { pr in
                    PRListRow(pr: pr)
                        .tag(pr)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 280)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    model.refreshPRList()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh PR list")
            }
        }
    }

    // MARK: - Column 3: Phase Detail

    @ViewBuilder
    private var phaseDetailView: some View {
        if model.selectedPR != nil {
            VStack(spacing: 0) {
                PipelineStatusView()
                    .environment(model)

                Divider()

                PhaseInputView(phase: model.selectedPhase)
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
                    .disabled(model.isAnyPhaseRunning || model.selectedConfiguration == nil || model.prNumber.isEmpty)
                }
            }
        } else {
            ContentUnavailableView(
                "Select a Pull Request",
                systemImage: "arrow.left.circle",
                description: Text("Choose a PR from the list to view its review data.")
            )
        }
    }

    // MARK: - Phase Output Views

    @ViewBuilder
    private var phaseOutputView: some View {
        switch model.selectedPhase {
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
        if let fullDiff = model.fullDiff {
            VStack(spacing: 0) {
                if model.effectiveDiff != nil {
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
                    effectiveDiff: model.effectiveDiff
                )
            }
            .sheet(isPresented: $showEffectiveDiff) {
                if let effectiveDiff = model.effectiveDiff {
                    EffectiveDiffView(
                        fullDiff: fullDiff,
                        effectiveDiff: effectiveDiff,
                        moveReport: model.moveReport
                    )
                    .frame(minWidth: 900, minHeight: 600)
                }
            }
        } else if let files = model.diffFiles {
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
        if let output = model.rulesOutput {
            RulesPhaseView(
                focusAreas: output.focusAreas,
                rules: output.rules,
                tasks: output.tasks
            )
        } else if case .running(let logs) = model.stateFor(model.selectedPhase) {
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
        if let output = model.evaluationOutput {
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
                    posted: model.commentOutput?.posted ?? false,
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
        if let output = model.reportOutput {
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

#Preview {
    ContentView()
        .environment(PRReviewModel(venvBinPath: "", environment: [:]))
}
