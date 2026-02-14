import Foundation
import PRRadarConfigService

public struct SetDefaultConfigurationUseCase: Sendable {

    private let settingsService: SettingsService

    public init(settingsService: SettingsService) {
        self.settingsService = settingsService
    }

    public func execute(id: UUID) throws -> AppSettings {
        var settings = settingsService.load()
        settingsService.setDefault(id: id, in: &settings)
        try settingsService.save(settings)
        return settings
    }
}
