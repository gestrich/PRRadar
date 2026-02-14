import Foundation
import PRRadarConfigService
import PRRadarModels

@Observable
@MainActor
public final class AppModel {

    let agentScriptPath: String
    let settingsModel: SettingsModel

    var allPRsModel: AllPRsModel?

    public init(agentScriptPath: String, settingsModel: SettingsModel) {
        self.agentScriptPath = agentScriptPath
        self.settingsModel = settingsModel

        Task { [weak self] in
            guard self != nil else { return }
            for await _ in settingsModel.observeChanges() {
                // React to settings changes if needed (e.g., active config was removed)
            }
        }
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

    // MARK: - Settings Forwarding (removed in Phase 4 when views use SettingsModel directly)

    var settings: AppSettings {
        settingsModel.settings
    }

    func addConfiguration(_ config: RepoConfiguration) {
        settingsModel.addConfiguration(config)
    }

    func removeConfiguration(id: UUID) {
        settingsModel.removeConfiguration(id: id)
    }

    func updateConfiguration(_ config: RepoConfiguration) {
        settingsModel.updateConfiguration(config)
    }

    func setDefault(id: UUID) {
        settingsModel.setDefault(id: id)
    }
}
