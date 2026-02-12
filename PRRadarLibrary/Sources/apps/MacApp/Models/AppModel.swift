import Foundation
import PRRadarConfigService
import PRRadarModels

@Observable
@MainActor
public final class AppModel {

    let agentScriptPath: String
    private let settingsService: SettingsService
    var settings: AppSettings

    var allPRsModel: AllPRsModel?

    public init(agentScriptPath: String) {
        self.agentScriptPath = agentScriptPath
        self.settingsService = SettingsService()
        self.settings = settingsService.load()
    }

    // MARK: - Config Selection

    func selectConfig(_ config: RepoConfiguration?) {
        if let config {
            let prRadarConfig = PRRadarConfig(
                repoPath: config.repoPath,
                outputDir: config.outputDir,
                agentScriptPath: agentScriptPath,
                githubToken: config.githubToken
            )
            allPRsModel = AllPRsModel(
                config: prRadarConfig,
                repoConfig: config
            )
        } else {
            allPRsModel = nil
        }
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
