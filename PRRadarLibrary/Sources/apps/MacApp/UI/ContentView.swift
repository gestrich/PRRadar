import PRRadarConfigService
import PRRadarModels
import SwiftUI

public struct ContentView: View {

    @Environment(AppModel.self) private var appModel
    @State private var selectedConfig: RepoConfiguration?
    @State private var selectedPR: PRModel?
    @AppStorage("selectedConfigID") private var savedConfigID: String = ""
    @AppStorage("selectedPRNumber") private var savedPRNumber: Int = 0
    @State private var showSettings = false
    @State private var showNewReview = false
    @State private var newPRNumber = ""
    @State private var showAnalyzeAll = false
    @State private var showAnalyzeAllProgress = false
    @State private var showRefreshProgress = false
    @AppStorage("daysLookBack") private var daysLookBack: Int = 7
    @AppStorage("selectedPRState") private var selectedPRStateString: String = "ALL"

    public init() {}

    private var allPRs: AllPRsModel? { appModel.allPRsModel }

    private var showRefreshError: Binding<Bool> {
        Binding(
            get: { if let model = allPRs, case .failed = model.state { return true } else { return false } },
            set: { if !$0 { Task { await allPRs?.load() } } }
        )
    }

    public var body: some View {
        NavigationSplitView {
            configSidebar
        } content: {
            prListView
        } detail: {
            detailView
        }
        .id(selectedConfig?.id)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gear")
                }
                .accessibilityIdentifier("settingsButton")
                .help("Manage configurations")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await selectedPR?.refreshPRData() }
                } label: {
                    if let pr = selectedPR, pr.operationMode == .refreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .accessibilityIdentifier("refreshButton")
                .help("Refresh PR data")
                .disabled(selectedPR == nil || selectedPR!.isAnyPhaseRunning || selectedPR!.prNumber.isEmpty)

                Button {
                    Task { await selectedPR?.runAnalysis() }
                } label: {
                    if let pr = selectedPR, pr.operationMode == .analyzing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "sparkles")
                    }
                }
                .accessibilityIdentifier("analyzeButton")
                .help("Analyze PR")
                .disabled(selectedPR == nil || selectedPR!.isAnyPhaseRunning || selectedPR!.prNumber.isEmpty)

                Button {
                    if let pr = selectedPR {
                        let path = "\(pr.config.absoluteOutputDir)/\(pr.prNumber)"
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }
                } label: {
                    Image(systemName: "folder")
                }
                .accessibilityIdentifier("folderButton")
                .help("Open PR data in Finder")
                .disabled(selectedPR == nil || selectedPR!.prNumber.isEmpty)

                Button {
                    if let pr = selectedPR,
                       let urlString = pr.metadata.url,
                       let url = URL(string: urlString) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "safari")
                }
                .accessibilityIdentifier("safariButton")
                .help("Open PR on GitHub")
                .disabled(selectedPR?.metadata.url == nil)
            }
        }
        .sheet(isPresented: $showSettings) {
            if let model = allPRs {
                SettingsView(model: model, appModel: appModel)
            }
        }
        .sheet(isPresented: $showAnalyzeAllProgress) {
            if let model = allPRs {
                AnalyzeAllProgressView(model: model, isPresented: $showAnalyzeAllProgress)
            }
        }
        .sheet(isPresented: $showRefreshProgress) {
            if let model = allPRs {
                RefreshAllProgressView(model: model, isPresented: $showRefreshProgress)
            }
        }
        .alert("Refresh Failed", isPresented: showRefreshError) {
            Button("OK") { Task { await allPRs?.load() } }
        } message: {
            if let model = allPRs, case .failed(let error, _) = model.state {
                Text(error)
            }
        }
        .task {
            if let config = appModel.settings.configurations.first(where: { $0.id.uuidString == savedConfigID }) {
                selectedConfig = config
            } else if let config = appModel.settings.defaultConfiguration {
                selectedConfig = config
            }
        }
        .onChange(of: selectedConfig) { old, new in
            guard let config = new, config.id != old?.id else { return }
            appModel.selectConfig(config)
            savedConfigID = config.id.uuidString
            selectedPR = nil
            savedPRNumber = 0
        }
        .onChange(of: selectedPR) { old, new in
            old?.cancelRefresh()
            if let pr = new {
                pr.loadDetail()
                Task { await pr.refreshDiff() }
                savedPRNumber = pr.metadata.number
            } else {
                savedPRNumber = 0
            }
        }
        .task {
            if savedPRNumber != 0, let pr = currentPRModels.first(where: { $0.metadata.number == savedPRNumber }) {
                selectedPR = pr
            }
        }
    }

    // MARK: - Column 1: Config Sidebar

    private var configSidebar: some View {
        List(appModel.settings.configurations, selection: $selectedConfig) { config in
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
            .accessibilityIdentifier("configRow_\(config.name)")
            .tag(config)
        }
        .accessibilityIdentifier("configSidebar")
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 150, ideal: 180)
    }

    // MARK: - Column 2: PR List

    private var prListView: some View {
        VStack(spacing: 0) {
            if allPRs != nil {
                prListFilterBar
                Divider()
                if filteredPRModels.isEmpty {
                    ContentUnavailableView(
                        "No Reviews Found",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(allPRs?.showOnlyWithPendingComments == true ? "No PRs with pending comments found." : "No PR review data found in the output directory.")
                    )
                } else {
                    List(filteredPRModels, selection: $selectedPR) { prModel in
                        PRListRow(prModel: prModel)
                            .tag(prModel)
                    }
                    .accessibilityIdentifier("prList")
                }
            } else {
                ContentUnavailableView(
                    "Select a Configuration",
                    systemImage: "folder",
                    description: Text("Choose a repo configuration from the sidebar.")
                )
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 280)
    }

    private var prListFilterBar: some View {
        HStack(spacing: 6) {
            Menu("\(daysLookBack)d") {
                ForEach([1, 7, 14, 30, 60, 90], id: \.self) { days in
                    Button("\(days) days") { daysLookBack = days }
                }
            }
            .accessibilityIdentifier("daysFilter")
            .help("Days to look back")

            Menu(stateFilterLabel) {
                Button("All") { selectedPRStateString = "ALL" }
                Divider()
                ForEach(PRState.allCases, id: \.self) { state in
                    Button(state.displayName) { selectedPRStateString = state.rawValue }
                }
            }
            .accessibilityIdentifier("stateFilter")
            .help("Filter by PR state")

            Toggle(isOn: Binding(
                get: { allPRs?.showOnlyWithPendingComments ?? false },
                set: { allPRs?.showOnlyWithPendingComments = $0 }
            )) {
                Image(systemName: "text.bubble")
            }
            .accessibilityIdentifier("pendingCommentsToggle")
            .help("Show only PRs with pending comments")
            .toggleStyle(.button)

            Button {
                if let model = allPRs, model.refreshAllState.isRunning {
                    showRefreshProgress = true
                } else {
                    Task { await allPRs?.refresh(since: sinceDate, state: selectedPRStateFilter) }
                }
            } label: {
                if let model = allPRs, model.refreshAllState.isRunning {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.small)
                        if let progressText = model.refreshAllState.progressText {
                            Text(progressText)
                                .font(.caption)
                                .monospacedDigit()
                        }
                    }
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .accessibilityIdentifier("refreshListButton")
            .help(allPRs?.refreshAllState.isRunning == true ? "Show progress" : "Refresh PR list")

            Spacer()

            Button {
                if let model = allPRs, model.analyzeAllState.isRunning {
                    showAnalyzeAllProgress = true
                } else {
                    showAnalyzeAll = true
                }
            } label: {
                if let model = allPRs, model.analyzeAllState.isRunning {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.small)
                        if let progressText = model.analyzeAllState.progressText {
                            Text(progressText)
                                .font(.caption)
                                .monospacedDigit()
                        }
                    }
                } else {
                    Image(systemName: "sparkles")
                }
            }
            .accessibilityIdentifier("analyzeAllButton")
            .help(allPRs?.analyzeAllState.isRunning == true ? "Show progress" : "Analyze all PRs since a date")
            .popover(isPresented: $showAnalyzeAll, arrowEdge: .bottom) {
                analyzeAllPopover
            }

            Button {
                newPRNumber = ""
                showNewReview = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityIdentifier("newReviewButton")
            .help("Start a new PR review")
            .popover(isPresented: $showNewReview, arrowEdge: .bottom) {
                newReviewPopover
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Column 3: Detail

    @ViewBuilder
    private var detailView: some View {
        if allPRs != nil {
            if let selectedPR {
                ReviewDetailView(prModel: selectedPR)
                    .id(selectedPR.metadata.number)
            } else {
                ContentUnavailableView(
                    "Select a Pull Request",
                    systemImage: "arrow.left.circle",
                    description: Text("Choose a PR from the list to view its review data.")
                )
            }
        } else {
            ContentUnavailableView(
                "Select a Configuration",
                systemImage: "folder",
                description: Text("Choose a repo configuration from the sidebar.")
            )
        }
    }

    // MARK: - New Review Popover

    @ViewBuilder
    private var newReviewPopover: some View {
        VStack(spacing: 12) {
            Text("New PR Review")
                .font(.headline)

            TextField("PR number", text: $newPRNumber)
                .accessibilityIdentifier("prNumberField")
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
                .onSubmit {
                    submitNewReview()
                }

            Button("Start Review") {
                submitNewReview()
            }
            .accessibilityIdentifier("startReviewButton")
            .disabled(Int(newPRNumber) == nil)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    @ViewBuilder
    private var analyzeAllPopover: some View {
        VStack(spacing: 12) {
            Text("Analyze All PRs")
                .font(.headline)

            Text("Last \(daysLookBack) days \u{00B7} State: \(stateFilterLabel)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Start") {
                let state = selectedPRStateFilter
                showAnalyzeAll = false
                Task { await allPRs?.analyzeAll(since: sinceDate, state: state) }
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    private var selectedPRStateFilter: PRState? {
        if selectedPRStateString == "ALL" { return nil }
        return PRState(rawValue: selectedPRStateString)
    }

    private var stateFilterLabel: String {
        selectedPRStateFilter?.displayName ?? "All"
    }

    private var sinceDate: Date {
        Calendar.current.date(byAdding: .day, value: -daysLookBack, to: Date()) ?? Date()
    }

    private func submitNewReview() {
        guard let number = Int(newPRNumber), let model = allPRs else { return }
        showNewReview = false
        Task {
            let fallback = PRMetadata.fallback(number: number)
            let newPR = PRModel(metadata: fallback, config: model.config, repoConfig: model.repoConfig)
            selectedPR = newPR
            await newPR.refreshDiff(force: true)
            await model.load()
            if let updated = currentPRModels.first(where: { $0.metadata.number == number }) {
                selectedPR = updated
            }
        }
    }

    // MARK: - Helpers

    private var currentPRModels: [PRModel] {
        allPRs?.currentPRModels ?? []
    }

    private var filteredPRModels: [PRModel] {
        allPRs?.filteredPRModels(since: sinceDate, state: selectedPRStateFilter) ?? []
    }

    private var isRefreshing: Bool {
        guard let model = allPRs else { return false }
        if case .refreshing = model.state { return true }
        return model.refreshAllState.isRunning
    }
}

#Preview {
    ContentView()
        .environment(AppModel(bridgeScriptPath: "/tmp/bridge.py"))
}
