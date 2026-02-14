import Foundation
import PRRadarConfigService

public struct SaveConfigurationUseCase: Sendable {

    private let settingsService: SettingsService

    public init(settingsService: SettingsService) {
        self.settingsService = settingsService
    }

    public func execute(config: RepositoryConfigurationJSON) throws -> AppSettings {
        var settings = settingsService.load()
        if let index = settings.configurations.firstIndex(where: { $0.id == config.id }) {
            settings.configurations[index] = config
        } else {
            settingsService.addConfiguration(config, to: &settings)
        }
        try settingsService.save(settings)
        return settings
    }
}
