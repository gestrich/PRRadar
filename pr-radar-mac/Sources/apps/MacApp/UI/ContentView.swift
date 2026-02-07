import PRRadarConfigService
import PRRadarModels
import SwiftUI

struct ContentView: View {

    @Environment(PRReviewModel.self) private var model
    @State private var showSettings = false
    @State private var showEffectiveDiff = false
    @State private var showCommentApproval = false

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            NavigationSplitView {
                sidebar
            } detail: {
                phaseDetail
            }

            PipelineStatusView()
                .environment(model)
        }
        .toolbar {
            toolbarContent
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(model)
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        @Bindable var model = model

        List(selection: $model.selectedPhase) {
            Section("Pipeline") {
                ForEach(PRRadarPhase.allCases, id: \.self) { phase in
                    sidebarRow(phase)
                        .tag(phase)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 160, ideal: 200)
    }

    @ViewBuilder
    private func sidebarRow(_ phase: PRRadarPhase) -> some View {
        HStack(spacing: 8) {
            phaseIcon(phase)
            VStack(alignment: .leading, spacing: 1) {
                Text(phaseName(phase))
                    .font(.body)
                Text(phaseSubtitle(phase))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusBadge(for: model.stateFor(phase))
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func phaseIcon(_ phase: PRRadarPhase) -> some View {
        Image(systemName: phaseIconName(phase))
            .foregroundStyle(.secondary)
            .frame(width: 20)
    }

    private func phaseIconName(_ phase: PRRadarPhase) -> String {
        switch phase {
        case .pullRequest: "doc.text.magnifyingglass"
        case .focusAreas: "scope"
        case .rules: "list.clipboard"
        case .tasks: "checklist"
        case .evaluations: "brain"
        case .report: "chart.bar.doc.horizontal"
        }
    }

    private func phaseName(_ phase: PRRadarPhase) -> String {
        switch phase {
        case .pullRequest: "Diff"
        case .focusAreas: "Focus Areas"
        case .rules: "Rules"
        case .tasks: "Tasks"
        case .evaluations: "Evaluations"
        case .report: "Report"
        }
    }

    private func phaseSubtitle(_ phase: PRRadarPhase) -> String {
        switch phase {
        case .pullRequest: "Phase 1"
        case .focusAreas: "Phase 2"
        case .rules: "Phase 3"
        case .tasks: "Phase 4"
        case .evaluations: "Phase 5"
        case .report: "Phase 6"
        }
    }

    @ViewBuilder
    private func statusBadge(for state: PRReviewModel.PhaseState) -> some View {
        switch state {
        case .idle:
            EmptyView()
        case .running:
            ProgressView()
                .controlSize(.mini)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var phaseDetail: some View {
        VStack(spacing: 0) {
            globalInputBar
            Divider()
            PhaseInputView(phase: model.selectedPhase)
                .environment(model)
                .padding()
            Divider()
            phaseOutputView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var globalInputBar: some View {
        @Bindable var model = model

        HStack(spacing: 12) {
            Picker("Config", selection: Binding(
                get: { model.selectedConfiguration?.id },
                set: { id in
                    if let id, let config = model.settings.configurations.first(where: { $0.id == id }) {
                        model.selectConfiguration(config)
                    }
                }
            )) {
                if model.settings.configurations.isEmpty {
                    Text("No configurations").tag(nil as UUID?)
                }
                ForEach(model.settings.configurations) { config in
                    Text(config.name).tag(config.id as UUID?)
                }
            }
            .frame(maxWidth: 200)

            HStack(spacing: 4) {
                Text("PR")
                    .foregroundStyle(.secondary)
                TextField("#", text: $model.prNumber)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }

            Spacer()

            Button("Run All") {
                Task { await model.runAllPhases() }
            }
            .disabled(model.isAnyPhaseRunning || model.selectedConfiguration == nil || model.prNumber.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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

#Preview {
    ContentView()
        .environment(PRReviewModel(venvBinPath: "", environment: [:]))
}
