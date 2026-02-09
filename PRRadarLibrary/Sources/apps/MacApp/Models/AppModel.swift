import Foundation
import PRRadarConfigService
import PRRadarModels

@Observable
@MainActor
public final class AppModel {

    let bridgeScriptPath: String
    private let settingsService: SettingsService
    var settings: AppSettings

    var selectedConfig: RepoConfiguration? {
        didSet {
            guard selectedConfig?.id != oldValue?.id else { return }
            if let config = selectedConfig {
                let prRadarConfig = PRRadarConfig(
                    repoPath: config.repoPath,
                    outputDir: config.outputDir,
                    bridgeScriptPath: bridgeScriptPath,
                    githubToken: config.githubToken
                )
                allPRsModel = AllPRsModel(
                    config: prRadarConfig,
                    repoConfig: config,
                    settingsService: settingsService
                )
            } else {
                allPRsModel = nil
            }
            selectedPR = nil
        }
    }

    var allPRsModel: AllPRsModel?
    var selectedPR: PRModel?

    public init(bridgeScriptPath: String) {
        self.bridgeScriptPath = bridgeScriptPath
        self.settingsService = SettingsService()
        self.settings = settingsService.load()
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

    private func persistSettings() {
        try? settingsService.save(settings)
    }
}
