import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels
import PRReviewFeature

@Observable
@MainActor
final class AllPRsModel {

    enum State {
        case uninitialized
        case loading
        case ready([PRModel])
        case refreshing([PRModel])
        case failed(String, prior: [PRModel]?)
    }

    enum RefreshAllState {
        case idle
        case refreshingList
        case refreshingPRs(current: Int, total: Int)

        var isRunning: Bool {
            switch self {
            case .idle: return false
            case .refreshingList, .refreshingPRs: return true
            }
        }

        var progressText: String? {
            if case .refreshingPRs(let current, let total) = self {
                return "\(current)/\(total)"
            }
            return nil
        }
    }

    enum AnalyzeAllState {
        case idle
        case running(logs: String, current: Int, total: Int)
        case completed(logs: String)
        case failed(error: String, logs: String)

        var isRunning: Bool {
            if case .running = self { return true }
            return false
        }
        
        var progressText: String? {
            if case .running(_, let current, let total) = self {
                return "\(current)/\(total)"
            }
            return nil
        }
    }

    private(set) var state: State = .uninitialized
    private(set) var refreshAllState: RefreshAllState = .idle
    private(set) var analyzeAllState: AnalyzeAllState = .idle
    var showOnlyWithPendingComments: Bool = false

    let config: PRRadarConfig
    let repoConfig: RepoConfiguration

    init(config: PRRadarConfig, repoConfig: RepoConfiguration) {
        self.config = config
        self.repoConfig = repoConfig
        Task { await load() }
    }

    // MARK: - PR Discovery

    func load() async {
        state = .loading
        let slug = PRDiscoveryService.repoSlug(fromRepoPath: repoConfig.repoPath)
        let metadata = PRDiscoveryService.discoverPRs(outputDir: repoConfig.outputDir, repoSlug: slug)
        let prModels = metadata.map { PRModel(metadata: $0, config: config, repoConfig: repoConfig) }
        state = .ready(prModels)
    }

    // MARK: - Refresh from GitHub

    func refresh(since: Date? = nil, state prState: PRState? = nil) async {
        let prior = currentPRModels
        self.state = .refreshing(prior ?? [])
        refreshAllState = .refreshingList

        let slug = PRDiscoveryService.repoSlug(fromRepoPath: repoConfig.repoPath)
        let useCase = FetchPRListUseCase(config: config)

        var prModels: [PRModel]?
        do {
            for try await progress in useCase.execute(state: prState, since: since, repoSlug: slug) {
                switch progress {
                case .running, .log, .progress:
                    break
                case .completed:
                    let metadata = PRDiscoveryService.discoverPRs(outputDir: repoConfig.outputDir, repoSlug: slug)
                    prModels = metadata.map { PRModel(metadata: $0, config: config, repoConfig: repoConfig) }
                    self.state = .ready(prModels!)
                case .failed(let error, _):
                    self.state = .failed(error, prior: prior)
                    refreshAllState = .idle
                    return
                }
            }
        } catch {
            self.state = .failed(error.localizedDescription, prior: prior)
            refreshAllState = .idle
            return
        }

        guard let models = prModels else {
            refreshAllState = .idle
            return
        }

        let prsToRefresh = filteredPRs(models, since: since, state: prState)

        let total = prsToRefresh.count
        refreshAllState = .refreshingPRs(current: 0, total: total)

        for (index, pr) in prsToRefresh.enumerated() {
            await pr.refreshPRData()
            refreshAllState = .refreshingPRs(current: index + 1, total: total)
        }

        refreshAllState = .idle
    }

    // MARK: - Analyze All

    func analyzeAll(since: Date, state prState: PRState? = nil) async {
        guard let models = currentPRModels else { return }

        let prsToAnalyze = filteredPRs(models, since: since, state: prState)
        let total = prsToAnalyze.count

        analyzeAllState = .running(logs: "Analyzing \(total) PRs...\n", current: 0, total: total)

        var analyzedCount = 0
        var failedCount = 0

        for (index, pr) in prsToAnalyze.enumerated() {
            let current = index + 1
            if case .running(let logs, _, _) = analyzeAllState {
                analyzeAllState = .running(
                    logs: logs + "[\(current)/\(total)] PR #\(pr.prNumber): \(pr.metadata.title)\n",
                    current: current,
                    total: total
                )
            }

            if await pr.runAnalysis() {
                analyzedCount += 1
            } else {
                failedCount += 1
            }
        }

        let logs = analyzeAllLogs
        analyzeAllState = .completed(
            logs: logs + "\nAnalyze-all complete: \(analyzedCount) succeeded, \(failedCount) failed\n"
        )
    }

    func dismissAnalyzeAllState() {
        analyzeAllState = .idle
    }

    // MARK: - Filtering

    func filteredPRModels(since: Date? = nil, state prState: PRState? = nil) -> [PRModel] {
        guard let models = currentPRModels else { return [] }
        return filteredPRs(models, since: since, state: prState)
    }

    func filteredPRs(_ models: [PRModel], since: Date? = nil, state prState: PRState? = nil) -> [PRModel] {
        var result = models
        if let since {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let standard = ISO8601DateFormatter()
            result = result.filter { pr in
                guard !pr.metadata.createdAt.isEmpty,
                      let date = fractional.date(from: pr.metadata.createdAt)
                        ?? standard.date(from: pr.metadata.createdAt) else { return true }
                return date >= since
            }
        }
        if let prState {
            result = result.filter { pr in
                PRState(rawValue: pr.metadata.state.uppercased()) == prState
            }
        }
        if showOnlyWithPendingComments {
            result = result.filter { $0.hasPendingComments }
        }
        return result
    }

    // MARK: - Helpers

    var currentPRModels: [PRModel]? {
        switch state {
        case .ready(let models): return models
        case .refreshing(let models): return models
        case .failed(_, let prior): return prior
        default: return nil
        }
    }

    private func reloadFromDisk() async {
        let slug = PRDiscoveryService.repoSlug(fromRepoPath: repoConfig.repoPath)
        let metadata = PRDiscoveryService.discoverPRs(outputDir: repoConfig.outputDir, repoSlug: slug)
        let prModels = metadata.map { PRModel(metadata: $0, config: config, repoConfig: repoConfig) }
        state = .ready(prModels)
    }

    private var analyzeAllLogs: String {
        if case .running(let logs, _, _) = analyzeAllState { return logs }
        return ""
    }

}
