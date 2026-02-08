import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels
import PRReviewFeature

@Observable
@MainActor
final class PRReviewModel {

    enum RefreshState {
        case idle
        case refreshing
        case failed(String)

        var isRefreshing: Bool {
            if case .refreshing = self { return true }
            return false
        }
    }

    enum AnalyzeAllState {
        case idle
        case running(logs: String)
        case completed(logs: String)
        case failed(error: String, logs: String)

        var isRunning: Bool {
            if case .running = self { return true }
            return false
        }
    }

    private(set) var settings: AppSettings
    private(set) var selectedConfiguration: RepoConfiguration?
    private(set) var discoveredPRs: [PRMetadata] = []
    private(set) var reviewModel: ReviewModel?
    private(set) var refreshState: RefreshState = .idle
    private(set) var analyzeAllState: AnalyzeAllState = .idle

    private let bridgeScriptPath: String
    private let settingsService: SettingsService

    init(bridgeScriptPath: String, settingsService: SettingsService = SettingsService()) {
        self.bridgeScriptPath = bridgeScriptPath
        self.settingsService = settingsService
        self.settings = settingsService.load()
    }

    // MARK: - Configuration Selection

    func selectConfiguration(_ config: RepoConfiguration) {
        selectedConfiguration = config
        let slug = PRDiscoveryService.repoSlug(fromRepoPath: config.repoPath)
        discoveredPRs = PRDiscoveryService.discoverPRs(outputDir: config.outputDir, repoSlug: slug)
        reviewModel = nil
    }

    func selectPR(_ pr: PRMetadata) {
        guard let selected = selectedConfiguration else { return }
        let config = makeConfig(from: selected)
        let review = ReviewModel(pr: pr, config: config, repoConfig: selected)
        review.loadExistingOutputs()
        reviewModel = review
    }

    // MARK: - PR List

    func refreshPRList() async {
        guard let selected = selectedConfiguration else { return }

        refreshState = .refreshing
        let config = makeConfig(from: selected)
        let slug = PRDiscoveryService.repoSlug(fromRepoPath: selected.repoPath)
        let useCase = FetchPRListUseCase(config: config)

        do {
            for try await progress in useCase.execute(repoSlug: slug) {
                switch progress {
                case .running:
                    break
                case .log:
                    break
                case .completed(let prs):
                    discoveredPRs = prs
                case .failed(let error, _):
                    refreshState = .failed(error)
                }
            }
        } catch {
            refreshState = .failed(error.localizedDescription)
        }

        if case .refreshing = refreshState {
            refreshState = .idle
        }
    }

    func dismissRefreshError() {
        refreshState = .idle
    }

    // MARK: - Analyze All

    func analyzeAll(since: String) async {
        guard let selected = selectedConfiguration else { return }

        analyzeAllState = .running(logs: "Analyzing all PRs since \(since)...\n")
        let config = makeConfig(from: selected)
        let rulesDir = selected.rulesDir.isEmpty ? nil : selected.rulesDir
        let slug = PRDiscoveryService.repoSlug(fromRepoPath: selected.repoPath)
        let useCase = AnalyzeAllUseCase(config: config)

        do {
            for try await progress in useCase.execute(since: since, rulesDir: rulesDir, repo: slug) {
                switch progress {
                case .running:
                    break
                case .log(let text):
                    if case .running(let logs) = analyzeAllState {
                        analyzeAllState = .running(logs: logs + text)
                    }
                case .completed:
                    let logs = analyzeAllLogs
                    analyzeAllState = .completed(logs: logs)
                case .failed(let error, let errorLogs):
                    let logs = analyzeAllLogs
                    analyzeAllState = .failed(error: error, logs: logs + errorLogs)
                }
            }
        } catch {
            let logs = analyzeAllLogs
            analyzeAllState = .failed(error: error.localizedDescription, logs: logs)
        }

        refreshPRListFromDisk()
    }

    func dismissAnalyzeAllState() {
        analyzeAllState = .idle
    }

    private var analyzeAllLogs: String {
        if case .running(let logs) = analyzeAllState { return logs }
        return ""
    }

    // MARK: - Configuration Management

    func addConfiguration(_ config: RepoConfiguration) {
        settingsService.addConfiguration(config, to: &settings)
        persistSettings()
        if settings.configurations.count == 1 {
            selectConfiguration(config)
        }
    }

    func removeConfiguration(id: UUID) {
        let wasSelected = selectedConfiguration?.id == id
        settingsService.removeConfiguration(id: id, from: &settings)
        persistSettings()
        if wasSelected {
            if let fallback = settings.defaultConfiguration {
                selectConfiguration(fallback)
            } else {
                selectedConfiguration = nil
                discoveredPRs = []
                reviewModel = nil
            }
        }
    }

    func updateConfiguration(_ config: RepoConfiguration) {
        if let idx = settings.configurations.firstIndex(where: { $0.id == config.id }) {
            settings.configurations[idx] = config
            persistSettings()
        }
    }

    func setDefault(id: UUID) {
        settingsService.setDefault(id: id, in: &settings)
        persistSettings()
    }

    func startNewReview(prNumber: Int) async {
        guard selectedConfiguration != nil else { return }

        let fallback = PRMetadata.fallback(number: prNumber)
        if !discoveredPRs.contains(where: { $0.number == prNumber }) {
            discoveredPRs.insert(fallback, at: 0)
        }
        if let match = discoveredPRs.first(where: { $0.number == prNumber }) {
            selectPR(match)
        }

        await reviewModel?.runDiff()

        refreshPRListFromDisk()
        if let updated = discoveredPRs.first(where: { $0.number == prNumber }) {
            selectPR(updated)
        }
    }

    // MARK: - Helpers

    private func makeConfig(from selected: RepoConfiguration) -> PRRadarConfig {
        PRRadarConfig(
            repoPath: selected.repoPath,
            outputDir: selected.outputDir,
            bridgeScriptPath: bridgeScriptPath
        )
    }

    private func refreshPRListFromDisk() {
        guard let selected = selectedConfiguration else { return }
        let slug = PRDiscoveryService.repoSlug(fromRepoPath: selected.repoPath)
        discoveredPRs = PRDiscoveryService.discoverPRs(outputDir: selected.outputDir, repoSlug: slug)
    }

    private func persistSettings() {
        try? settingsService.save(settings)
    }
}
