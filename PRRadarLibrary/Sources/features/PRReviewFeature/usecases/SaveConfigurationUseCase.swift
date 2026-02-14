import Foundation
import PRRadarConfigService

public struct SaveConfigurationUseCase: Sendable {

    private let settingsService: SettingsService

    public init(settingsService: SettingsService) {
        self.settingsService = settingsService
    }

    public func execute(config: RepoConfiguration, settings: AppSettings, isNew: Bool) throws -> AppSettings {
        var updated = settings
        if isNew {
            settingsService.addConfiguration(config, to: &updated)
        } else {
            guard let index = updated.configurations.firstIndex(where: { $0.id == config.id }) else {
                throw SaveConfigurationError.configurationNotFound(config.id)
            }
            updated.configurations[index] = config
        }
        try settingsService.save(updated)
        return updated
    }
}

public enum SaveConfigurationError: LocalizedError {
    case configurationNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .configurationNotFound(let id):
            "Configuration not found: \(id)"
        }
    }
}
