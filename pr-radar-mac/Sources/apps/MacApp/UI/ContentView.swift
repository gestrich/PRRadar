import PRRadarConfigService
import PRRadarModels
import SwiftUI

struct ContentView: View {

    @Environment(PRReviewModel.self) private var model
    @State private var selectedConfig: RepoConfiguration?
    @State private var selectedPR: PRMetadata?
    @AppStorage("selectedConfigID") private var savedConfigID: String = ""
    @AppStorage("selectedPRNumber") private var savedPRNumber: Int = 0
    @State private var showSettings = false
    @State private var showNewReview = false
    @State private var newPRNumber = ""
    @State private var showAnalyzeAll = false
    @State private var analyzeAllSinceDate = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date()

    private var showRefreshError: Binding<Bool> {
        Binding(
            get: { if case .failed = model.refreshState { return true } else { return false } },
            set: { if !$0 { model.dismissRefreshError() } }
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
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(model)
        }
        .alert("Refresh Failed", isPresented: showRefreshError) {
            Button("OK") { model.dismissRefreshError() }
        } message: {
            if case .failed(let error) = model.refreshState {
                Text(error)
            }
        }
        .task {
            if let config = model.settings.configurations.first(where: { $0.id.uuidString == savedConfigID }) {
                selectedConfig = config
                model.selectConfiguration(config)
                if savedPRNumber != 0, let pr = model.discoveredPRs.first(where: { $0.number == savedPRNumber }) {
                    selectedPR = pr
                    model.selectPR(pr)
                }
            } else if let config = model.settings.defaultConfiguration {
                selectedConfig = config
                model.selectConfiguration(config)
            }
        }
        .onChange(of: selectedConfig) { old, new in
            guard let config = new, config.id != old?.id else { return }
            guard config != model.selectedConfiguration else { return }
            model.selectConfiguration(config)
            savedConfigID = config.id.uuidString
            selectedPR = nil
            savedPRNumber = 0
        }
        .onChange(of: selectedPR) { _, new in
            if let pr = new {
                guard pr != model.selectedPR else { return }
                model.selectPR(pr)
                savedPRNumber = pr.number
            } else {
                savedPRNumber = 0
            }
        }
    }

    // MARK: - Column 1: Config Sidebar

    private var configSidebar: some View {
        List(model.settings.configurations, selection: $selectedConfig) { config in
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
            if selectedConfig != nil {
                if model.discoveredPRs.isEmpty {
                    ContentUnavailableView(
                        "No Reviews Found",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("No PR review data found in the output directory.")
                    )
                } else {
                    List(model.discoveredPRs, selection: $selectedPR) { pr in
                        PRListRow(pr: pr)
                            .tag(pr)
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
                Button {
                    Task { await model.refreshPRList() }
                } label: {
                    if case .refreshing = model.refreshState {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .help("Refresh PR list")
                .disabled(model.refreshState.isRefreshing || selectedConfig == nil)
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    showAnalyzeAll = true
                } label: {
                    if model.analyzeAllState.isRunning {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "sparkles")
                    }
                }
                .help("Analyze all PRs since a date")
                .disabled(selectedConfig == nil || model.analyzeAllState.isRunning)
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
                .disabled(selectedConfig == nil)
                .popover(isPresented: $showNewReview, arrowEdge: .bottom) {
                    newReviewPopover
                }
            }
        }
    }

    // MARK: - Column 3: Detail

    @ViewBuilder
    private var detailView: some View {
        if let selectedConfig {
            if let selectedPR,
               case .hasConfig(let ctx) = model.state,
               let review = ctx.review {
                ReviewDetailView(config: selectedConfig, review: review)
                    .id(selectedPR.number)
                    .environment(model)
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

            DatePicker("Since", selection: $analyzeAllSinceDate, displayedComponents: .date)
                .datePickerStyle(.field)
                .frame(width: 200)

            Button("Start") {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                let sinceString = formatter.string(from: analyzeAllSinceDate)
                showAnalyzeAll = false
                Task { await model.analyzeAll(since: sinceString) }
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    private func submitNewReview() {
        guard let number = Int(newPRNumber) else { return }
        showNewReview = false
        Task {
            await model.startNewReview(prNumber: number)
            selectedPR = model.selectedPR
            if let pr = selectedPR { savedPRNumber = pr.number }
        }
    }
}

#Preview {
    ContentView()
        .environment(PRReviewModel(venvBinPath: "", environment: [:]))
}
