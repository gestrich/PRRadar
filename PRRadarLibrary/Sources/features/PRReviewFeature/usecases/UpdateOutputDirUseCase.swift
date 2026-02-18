import Foundation
import PRRadarConfigService

public struct UpdateOutputDirUseCase: Sendable {

    private let settingsService: SettingsService

    public init(settingsService: SettingsService) {
        self.settingsService = settingsService
    }

    public func execute(outputDir: String) throws -> AppSettings {
        var settings = settingsService.load()
        settings.outputDir = outputDir
        try settingsService.save(settings)
        return settings
    }
}
