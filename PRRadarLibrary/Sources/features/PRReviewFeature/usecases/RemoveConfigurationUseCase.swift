import Foundation
import PRRadarConfigService

public struct RemoveConfigurationUseCase: Sendable {

    private let settingsService: SettingsService

    public init(settingsService: SettingsService) {
        self.settingsService = settingsService
    }

    public func execute(id: UUID) throws -> AppSettings {
        var settings = settingsService.load()
        settingsService.removeConfiguration(id: id, from: &settings)
        try settingsService.save(settings)
        return settings
    }
}
