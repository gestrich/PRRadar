import PRRadarConfigService
import PRRadarModels
import SwiftUI

public struct ContentView: View {

    @State private var allPRs: AllPRsModel?
    @State private var settingsService = SettingsService()
    @State private var settings: AppSettings
    @State private var selectedConfig: RepoConfiguration?
    @State private var selectedPR: PRModel?
    @AppStorage("selectedConfigID") private var savedConfigID: String = ""
    @AppStorage("selectedPRNumber") private var savedPRNumber: Int = 0
    @State private var showSettings = false
    @State private var showNewReview = false
    @State private var newPRNumber = ""
    @State private var showAnalyzeAll = false
    @State private var showAnalyzeAllProgress = false
    @AppStorage("daysLookBack") private var daysLookBack: Int = 7
    @AppStorage("selectedPRState") private var selectedPRStateString: String = "ALL"
    
    let bridgeScriptPath: String
    
    public init(bridgeScriptPath: String) {
        self.bridgeScriptPath = bridgeScriptPath
        let service = SettingsService()
        let loadedSettings = service.load()
        _settings = State(initialValue: loadedSettings)
    }

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
                .help("Manage configurations")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button("Run All") {
                    Task { await selectedPR?.runAllPhases() }
                }
                .disabled(selectedPR == nil || selectedPR!.isAnyPhaseRunning || selectedPR!.prNumber.isEmpty)

                Button {
                    if let pr = selectedPR {
                        let path = "\(pr.config.absoluteOutputDir)/\(pr.prNumber)"
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }
                } label: {
                    Image(systemName: "folder")
                }
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
                .help("Open PR on GitHub")
                .disabled(selectedPR?.metadata.url == nil)
            }
        }
        .sheet(isPresented: $showSettings) {
            if let model = allPRs {
                SettingsView(model: model, settings: $settings)
            }
        }
        .sheet(isPresented: $showAnalyzeAllProgress) {
            if let model = allPRs {
                AnalyzeAllProgressView(model: model, isPresented: $showAnalyzeAllProgress)
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
            if let config = settings.configurations.first(where: { $0.id.uuidString == savedConfigID }) {
                selectedConfig = config
            } else if let config = settings.defaultConfiguration {
                selectedConfig = config
            }
        }
        .onChange(of: selectedConfig) { old, new in
            guard let config = new, config.id != old?.id else { return }
            savedConfigID = config.id.uuidString
            selectedPR = nil
            savedPRNumber = 0
            createModelForConfig(config)
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
        List(settings.configurations, selection: $selectedConfig) { config in
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
            .help("Days to look back")

            Menu(stateFilterLabel) {
                Button("All") { selectedPRStateString = "ALL" }
                Divider()
                ForEach(PRState.allCases, id: \.self) { state in
                    Button(state.displayName) { selectedPRStateString = state.rawValue }
                }
            }
            .help("Filter by PR state")

            Toggle(isOn: Binding(
                get: { allPRs?.showOnlyWithPendingComments ?? false },
                set: { allPRs?.showOnlyWithPendingComments = $0 }
            )) {
                Image(systemName: "text.bubble")
            }
            .help("Show only PRs with pending comments")
            .toggleStyle(.button)

            Button {
                Task { await allPRs?.refresh(since: sinceDate, state: selectedPRStateFilter) }
            } label: {
                if let model = allPRs, case .refreshing = model.state {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .help("Refresh PR list")
            .disabled(isRefreshing)

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
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
                .onSubmit {
                    submitNewReview()
                }

            Button("Start Review") {
                submitNewReview()
            }
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
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                let sinceString = formatter.string(from: sinceDate)
                let state = selectedPRStateFilter
                showAnalyzeAll = false
                Task { await allPRs?.analyzeAll(since: sinceString, state: state) }
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
            // Setting selectedPR triggers .onChange → loadDetail + refreshDiff (auto-fetches since no cache)
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
        guard let model = allPRs else { return [] }
        switch model.state {
        case .ready(let models): return models
        case .refreshing(let models): return models
        case .failed(_, let prior): return prior ?? []
        default: return []
        }
    }

    private var filteredPRModels: [PRModel] {
        var models = currentPRModels
        let cutoff = sinceDate
        models = models.filter { pr in
            guard !pr.metadata.createdAt.isEmpty else { return true }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = formatter.date(from: pr.metadata.createdAt)
                ?? ISO8601DateFormatter().date(from: pr.metadata.createdAt)
            else { return true }
            return date >= cutoff
        }
        if let stateFilter = selectedPRStateFilter {
            models = models.filter { pr in
                PRState(rawValue: pr.metadata.state.uppercased()) == stateFilter
            }
        }
        if let allPRs = allPRs, allPRs.showOnlyWithPendingComments {
            models = models.filter { $0.hasPendingComments }
        }
        return models
    }

    private var isRefreshing: Bool {
        guard let model = allPRs else { return false }
        if case .refreshing = model.state { return true }
        return false
    }
    
    private func createModelForConfig(_ config: RepoConfiguration) {
        let prRadarConfig = PRRadarConfig(
            repoPath: config.repoPath,
            outputDir: config.outputDir,
            bridgeScriptPath: bridgeScriptPath,
            githubToken: config.githubToken
        )
        allPRs = AllPRsModel(
            config: prRadarConfig,
            repoConfig: config,
            settingsService: settingsService
        )
    }
}

#Preview {
    ContentView(bridgeScriptPath: "/tmp/bridge.py")
}
