import PRRadarConfigService
import SwiftUI

struct ContentView: View {

    @Environment(PRReviewModel.self) private var model
    @State private var showSettings = false
    @State private var showNewReview = false
    @State private var newPRNumber = ""

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
            switch model.state {
            case .noConfig:
                ContentUnavailableView(
                    "Select a Configuration",
                    systemImage: "folder",
                    description: Text("Choose a repo configuration from the sidebar.")
                )
            case .hasConfig(let ctx) where ctx.prs.isEmpty:
                ContentUnavailableView(
                    "No Reviews Found",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("No PR review data found in the output directory.")
                )
            case .hasConfig:
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
            ToolbarItem(placement: .automatic) {
                Button {
                    newPRNumber = ""
                    showNewReview = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Start a new PR review")
                .disabled(model.selectedConfiguration == nil)
                .popover(isPresented: $showNewReview, arrowEdge: .bottom) {
                    newReviewPopover
                }
            }
        }
    }

    // MARK: - Column 3: Detail

    @ViewBuilder
    private var detailView: some View {
        switch model.state {
        case .noConfig:
            ContentUnavailableView(
                "Select a Configuration",
                systemImage: "folder",
                description: Text("Choose a repo configuration from the sidebar.")
            )
        case .hasConfig(let ctx):
            if let review = ctx.review {
                ReviewDetailView(config: ctx.config, review: review)
                    .id(review.pr.number)
                    .environment(model)
            } else {
                ContentUnavailableView(
                    "Select a Pull Request",
                    systemImage: "arrow.left.circle",
                    description: Text("Choose a PR from the list to view its review data.")
                )
            }
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

    private func submitNewReview() {
        guard let number = Int(newPRNumber) else { return }
        showNewReview = false
        Task { await model.startNewReview(prNumber: number) }
    }
}

#Preview {
    ContentView()
        .environment(PRReviewModel(venvBinPath: "", environment: [:]))
}
