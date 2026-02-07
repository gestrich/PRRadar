import Foundation
import PRRadarConfigService
import PRReviewFeature

@Observable
@MainActor
final class PRReviewModel {

    enum State {
        case idle
        case running(logs: String)
        case completed(files: [String], logs: String)
        case failed(error: String, logs: String)
    }

    private(set) var state: State = .idle
    private(set) var settings: AppSettings

    var selectedConfiguration: RepoConfiguration? {
        get {
            let savedID = UserDefaults.standard.string(forKey: "selectedConfigID")
                .flatMap(UUID.init(uuidString:))
            if let savedID, let config = settings.configurations.first(where: { $0.id == savedID }) {
                return config
            }
            return settings.defaultConfiguration
        }
        set {
            if let id = newValue?.id {
                UserDefaults.standard.set(id.uuidString, forKey: "selectedConfigID")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedConfigID")
            }
        }
    }

    var prNumber: String {
        get { access(keyPath: \.prNumber); return UserDefaults.standard.string(forKey: "prNumber") ?? "" }
        set { withMutation(keyPath: \.prNumber) { UserDefaults.standard.set(newValue, forKey: "prNumber") } }
    }

    private let venvBinPath: String
    private let environment: [String: String]
    private let settingsService: SettingsService

    init(venvBinPath: String, environment: [String: String], settingsService: SettingsService = SettingsService()) {
        self.venvBinPath = venvBinPath
        self.environment = environment
        self.settingsService = settingsService
        self.settings = settingsService.load()
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    func addConfiguration(_ config: RepoConfiguration) {
        settingsService.addConfiguration(config, to: &settings)
        persistSettings()
        if settings.configurations.count == 1 {
            selectedConfiguration = config
        }
    }

    func removeConfiguration(id: UUID) {
        let wasSelected = selectedConfiguration?.id == id
        settingsService.removeConfiguration(id: id, from: &settings)
        persistSettings()
        if wasSelected {
            selectedConfiguration = settings.defaultConfiguration
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

    func selectConfiguration(_ config: RepoConfiguration) {
        selectedConfiguration = config
        state = .idle
    }

    func runDiff() async {
        guard let selected = selectedConfiguration else { return }

        let config = PRRadarConfig(
            venvBinPath: venvBinPath,
            repoPath: selected.repoPath,
            outputDir: selected.outputDir
        )

        state = .running(logs: "Looking for prradar in: \(venvBinPath)\n")

        let useCase = FetchDiffUseCase(
            config: config,
            environment: environment
        )

        do {
            for try await progress in useCase.execute(prNumber: prNumber) {
                switch progress {
                case .running:
                    break
                case .completed(let files):
                    if case .running(let logs) = state {
                        state = .completed(files: files, logs: logs)
                    }
                case .failed(let error):
                    if case .running(let logs) = state {
                        state = .failed(error: error, logs: logs)
                    }
                }
            }
        } catch {
            let logs = if case .running(let l) = state { l } else { "" }
            state = .failed(error: error.localizedDescription, logs: logs)
        }
    }

    private func persistSettings() {
        try? settingsService.save(settings)
    }
}
