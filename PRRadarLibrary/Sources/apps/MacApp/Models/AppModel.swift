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
        Task { await observeSettingsModel() }
    }

    private func observeSettingsModel() async {
        for await _ in settingsModel.observeChanges() {
            // React to settings changes if needed (e.g., active config was removed)
        }
    }

    // MARK: - Config Selection

    func selectConfig(_ config: RepoConfiguration?) {
        if let config {
            let prRadarConfig = PRRadarConfig(
                repoPath: config.repoPath,
                outputDir: config.outputDir,
                agentScriptPath: agentScriptPath
            )
            allPRsModel = AllPRsModel(
                config: prRadarConfig,
                repoConfig: config
            )
        } else {
            allPRsModel = nil
        }
    }

}
