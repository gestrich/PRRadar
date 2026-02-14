import Foundation
import PRRadarConfigService

public struct RemoveConfigurationUseCase: Sendable {

    private let settingsService: SettingsService

    public init(settingsService: SettingsService) {
        self.settingsService = settingsService
    }

    public func execute(id: UUID, settings: AppSettings) throws -> AppSettings {
        var updated = settings
        settingsService.removeConfiguration(id: id, from: &updated)
        try settingsService.save(updated)
        return updated
    }
}
