import PRRadarConfigService
import PRRadarModels
import SwiftUI

struct ContentView: View {

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
    @State private var analyzeAllSinceDate = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date()
    
    let bridgeScriptPath: String
    
    init(bridgeScriptPath: String) {
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

    var body: some View {
        NavigationSplitView {
            configSidebar
        } content: {
            prListView
        } detail: {
            detailView
        }
        .id(selectedConfig?.id)
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
        .onChange(of: selectedPR) { _, new in
            if let pr = new {
                pr.loadDetail()
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

    private var prListView: some View {
        Group {
            if allPRs != nil {
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
        .toolbar {
            ToolbarItem(placement: .automatic) {
                DatePicker("Since", selection: $analyzeAllSinceDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .help("Filter PRs by date")
            }
            ToolbarItem(placement: .automatic) {
                Toggle(isOn: Binding(
                    get: { allPRs?.showOnlyWithPendingComments ?? false },
                    set: { allPRs?.showOnlyWithPendingComments = $0 }
                )) {
                    Image(systemName: "text.bubble")
                }
                .help("Show only PRs with pending comments")
                .toggleStyle(.button)
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await allPRs?.refresh(since: analyzeAllSinceDate) }
                } label: {
                    if let model = allPRs, case .refreshing = model.state {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .help("Refresh PR list")
                .disabled(isRefreshing || allPRs == nil)
            }
            ToolbarItem(placement: .automatic) {
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
                .disabled(allPRs == nil)
                .popover(isPresented: $showAnalyzeAll, arrowEdge: .bottom) {
                    analyzeAllPopover
                }
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    newPRNumber = ""
                    showNewReview = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Start a new PR review")
                .disabled(allPRs == nil)
                .popover(isPresented: $showNewReview, arrowEdge: .bottom) {
                    newReviewPopover
                }
            }
        }
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

            Text("Since: \(formattedSinceDate)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Start") {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                let sinceString = formatter.string(from: analyzeAllSinceDate)
                showAnalyzeAll = false
                Task { await allPRs?.analyzeAll(since: sinceString) }
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }
    
    private var formattedSinceDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: analyzeAllSinceDate)
    }

    private func submitNewReview() {
        guard let number = Int(newPRNumber), let model = allPRs else { return }
        showNewReview = false
        Task {
            let fallback = PRMetadata.fallback(number: number)
            let newPR = PRModel(metadata: fallback, config: model.config, repoConfig: model.repoConfig)
            selectedPR = newPR
            await newPR.runDiff()
            await model.load()
            if let updated = currentPRModels.first(where: { $0.metadata.number == number }) {
                selectedPR = updated
                updated.loadDetail()
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
        let models = currentPRModels
        guard let allPRs = allPRs, allPRs.showOnlyWithPendingComments else {
            return models
        }
        return models.filter { $0.hasPendingComments }
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
