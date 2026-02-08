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
    private(set) var analyzeAllState: AnalyzeAllState = .idle

    let config: PRRadarConfig
    let repoConfig: RepoConfiguration

    private let settingsService: SettingsService
    private(set) var settings: AppSettings

    init(config: PRRadarConfig, repoConfig: RepoConfiguration, settingsService: SettingsService = SettingsService()) {
        self.config = config
        self.repoConfig = repoConfig
        self.settingsService = settingsService
        self.settings = settingsService.load()
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

    func refresh() async {
        let prior = currentPRModels
        state = .refreshing(prior ?? [])

        let slug = PRDiscoveryService.repoSlug(fromRepoPath: repoConfig.repoPath)
        let useCase = FetchPRListUseCase(config: config)

        do {
            for try await progress in useCase.execute(repoSlug: slug) {
                switch progress {
                case .running, .log, .progress:
                    break
                case .completed:
                    let metadata = PRDiscoveryService.discoverPRs(outputDir: repoConfig.outputDir, repoSlug: slug)
                    let prModels = metadata.map { PRModel(metadata: $0, config: config, repoConfig: repoConfig) }
                    state = .ready(prModels)
                case .failed(let error, _):
                    state = .failed(error, prior: prior)
                }
            }
        } catch {
            state = .failed(error.localizedDescription, prior: prior)
        }
    }

    // MARK: - Analyze All

    func analyzeAll(since: String) async {
        analyzeAllState = .running(logs: "Analyzing all PRs since \(since)...\n", current: 0, total: 0)
        let rulesDir = repoConfig.rulesDir.isEmpty ? nil : repoConfig.rulesDir
        let slug = PRDiscoveryService.repoSlug(fromRepoPath: repoConfig.repoPath)
        let useCase = AnalyzeAllUseCase(config: config)

        do {
            for try await progress in useCase.execute(since: since, rulesDir: rulesDir, repo: slug) {
                switch progress {
                case .running:
                    break
                case .progress(let current, let total):
                    if case .running(let logs, _, _) = analyzeAllState {
                        analyzeAllState = .running(logs: logs, current: current, total: total)
                    }
                case .log(let text):
                    if case .running(let logs, let current, let total) = analyzeAllState {
                        analyzeAllState = .running(logs: logs + text, current: current, total: total)
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

        await reloadFromDisk()
    }

    func dismissAnalyzeAllState() {
        analyzeAllState = .idle
    }

    // MARK: - Configuration Management

    func addConfiguration(_ config: RepoConfiguration) {
        settingsService.addConfiguration(config, to: &settings)
        persistSettings()
    }

    func removeConfiguration(id: UUID) {
        settingsService.removeConfiguration(id: id, from: &settings)
        persistSettings()
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

    // MARK: - Helpers

    private var currentPRModels: [PRModel]? {
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

    private func persistSettings() {
        try? settingsService.save(settings)
    }
}
