import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels
import PRReviewFeature

struct AuthorOption {
    let login: String
    let name: String

    var displayLabel: String {
        if name.isEmpty || name == login {
            return login
        }
        return "\(name) (\(login))"
    }
}

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
        case running(logs: String, current: Int, total: Int)
        case completed(logs: String)

        var isRunning: Bool {
            switch self {
            case .idle, .completed: return false
            case .running: return true
            }
        }

        var progressText: String? {
            if case .running(_, let current, let total) = self, total > 0 {
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

    let config: RepositoryConfiguration

    init(config: RepositoryConfiguration) {
        self.config = config
        Task {
            await load()
            await refresh(filter: config.makeFilter())
        }
    }

    // MARK: - PR Discovery

    func load() async {
        state = .loading
        let slug = PRDiscoveryService.repoSlug(fromRepoPath: config.repoPath)
        let metadata = PRDiscoveryService.discoverPRs(outputDir: config.outputDir, repoSlug: slug)
        let prModels = metadata.map { PRModel(metadata: $0, config: config) }
        state = .ready(prModels)
    }

    // MARK: - Refresh from GitHub

    func refresh(filter: PRFilter) async {
        let prior = currentPRModels
        self.state = .refreshing(prior ?? [])
        refreshAllState = .running(logs: "Fetching PR list from GitHub...\n", current: 0, total: 0)

        let slug = PRDiscoveryService.repoSlug(fromRepoPath: config.repoPath)
        let useCase = FetchPRListUseCase(config: config)

        var updatedMetadata: [PRMetadata]?
        do {
            for try await progress in useCase.execute(filter: filter, repoSlug: slug) {
                switch progress {
                case .running, .progress:
                    break
                case .log(let text):
                    appendRefreshLog(text)
                case .prepareOutput: break
                case .prepareToolUse: break
                case .taskEvent: break
                case .completed:
                    updatedMetadata = PRDiscoveryService.discoverPRs(outputDir: config.outputDir, repoSlug: slug)
                case .failed(let error, _):
                    self.state = .failed(error, prior: prior)
                    refreshAllState = .completed(logs: refreshAllLogs + "Failed: \(error)\n")
                    return
                }
            }
        } catch {
            self.state = .failed(error.localizedDescription, prior: prior)
            refreshAllState = .completed(logs: refreshAllLogs + "Failed: \(error.localizedDescription)\n")
            return
        }

        guard let metadata = updatedMetadata else {
            refreshAllState = .completed(logs: refreshAllLogs + "No PRs found.\n")
            return
        }

        let existingByID = Dictionary(uniqueKeysWithValues: (prior ?? []).map { ($0.id, $0) })
        let mergedModels = metadata.map { meta -> PRModel in
            if let existing = existingByID[meta.id] {
                existing.updateMetadata(meta)
                return existing
            }
            return PRModel(metadata: meta, config: config)
        }
        self.state = .ready(mergedModels)

        let prsToRefresh = filteredPRs(mergedModels, filter: filter)
        let total = prsToRefresh.count
        appendRefreshLog("Found \(metadata.count) PRs, refreshing \(total)...\n")
        refreshAllState = .running(logs: refreshAllLogs, current: 0, total: total)

        for (index, pr) in prsToRefresh.enumerated() {
            let current = index + 1
            appendRefreshLog("[\(current)/\(total)] PR \(pr.metadata.displayNumber): \(pr.metadata.title)\n")
            refreshAllState = .running(logs: refreshAllLogs, current: current, total: total)
            await pr.refreshPRData()
        }

        refreshAllState = .completed(logs: refreshAllLogs + "\nRefresh complete.\n")
    }

    func dismissRefreshAllState() {
        refreshAllState = .idle
    }

    // MARK: - Delete PR Data

    func deletePRData(for prModel: PRModel) async throws {
        let refreshedMetadata = try await DeletePRDataUseCase(config: config)
            .execute(prNumber: prModel.metadata.number)
        prModel.resetAfterDataDeletion(metadata: refreshedMetadata)
    }

    // MARK: - Analyze All

    func analyzeAll(filter: PRFilter, ruleFilePaths: [String]? = nil) async {
        guard let models = currentPRModels else { return }

        let prsToAnalyze = filteredPRs(models, filter: filter)
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

            if await pr.runAnalysis(ruleFilePaths: ruleFilePaths) {
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

    func filteredPRModels(filter: PRFilter) -> [PRModel] {
        guard let models = currentPRModels else { return [] }
        return filteredPRs(models, filter: filter)
    }

    var availableAuthors: [AuthorOption] {
        guard let models = currentPRModels else { return [] }
        let prAuthors = models.map { AuthorOption(login: $0.metadata.author.login, name: $0.metadata.author.name) }
        let cache = AuthorCacheService().load()
        let cacheAuthors = cache.entries.values.map { AuthorOption(login: $0.login, name: $0.name) }
        var seen = Set<String>()
        var result: [AuthorOption] = []
        for author in prAuthors + cacheAuthors {
            if !author.login.isEmpty && seen.insert(author.login).inserted {
                result.append(author)
            }
        }
        return result.sorted { $0.displayLabel.localizedCaseInsensitiveCompare($1.displayLabel) == .orderedAscending }
    }

    func filteredPRs(_ models: [PRModel], filter: PRFilter = PRFilter()) -> [PRModel] {
        var result = models
        if let dateFilter = filter.dateFilter {
            let since = dateFilter.date
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let standard = ISO8601DateFormatter()
            // Pick the date field matching the filter type.
            // PRMetadata only has createdAt and updatedAt — merged/closed
            // dates aren't stored locally, so we fall back to updatedAt.
            // If the date is missing or unparseable, include the PR (safe default).
            result = result.filter { pr in
                let dateString: String? = switch dateFilter {
                case .createdSince:
                    pr.metadata.createdAt
                case .updatedSince, .mergedSince, .closedSince:
                    pr.metadata.updatedAt ?? pr.metadata.createdAt
                }
                guard let dateString, !dateString.isEmpty,
                      let date = fractional.date(from: dateString)
                        ?? standard.date(from: dateString) else { return true }
                return date >= since
            }
        }
        if let prState = filter.state {
            result = result.filter { pr in
                PRState(rawValue: pr.metadata.state.uppercased()) == prState
            }
        }
        if let baseBranch = filter.baseBranch, !baseBranch.isEmpty {
            result = result.filter { $0.metadata.baseRefName == baseBranch }
        }
        if let authorLogin = filter.authorLogin, !authorLogin.isEmpty {
            result = result.filter { $0.metadata.author.login == authorLogin }
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
        let slug = PRDiscoveryService.repoSlug(fromRepoPath: config.repoPath)
        let metadata = PRDiscoveryService.discoverPRs(outputDir: config.outputDir, repoSlug: slug)
        let prModels = metadata.map { PRModel(metadata: $0, config: config) }
        state = .ready(prModels)
    }

    private var refreshAllLogs: String {
        if case .running(let logs, _, _) = refreshAllState { return logs }
        return ""
    }

    private func appendRefreshLog(_ text: String) {
        if case .running(let logs, let current, let total) = refreshAllState {
            refreshAllState = .running(logs: logs + text, current: current, total: total)
        }
    }

    private var analyzeAllLogs: String {
        if case .running(let logs, _, _) = analyzeAllState { return logs }
        return ""
    }

}
