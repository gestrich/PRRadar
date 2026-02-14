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

    func selectConfig(_ jsonConfig: RepositoryConfigurationJSON?) {
        if let jsonConfig {
            let config = RepositoryConfiguration(from: jsonConfig, agentScriptPath: agentScriptPath)
            allPRsModel = AllPRsModel(config: config)
        } else {
            allPRsModel = nil
        }
    }

}
