import Foundation
import PRRadarConfigService

public struct SetDefaultConfigurationUseCase: Sendable {

    private let settingsService: SettingsService

    public init(settingsService: SettingsService) {
        self.settingsService = settingsService
    }

    public func execute(id: UUID, settings: AppSettings) throws -> AppSettings {
        var updated = settings
        settingsService.setDefault(id: id, in: &updated)
        try settingsService.save(updated)
        return updated
    }
}
