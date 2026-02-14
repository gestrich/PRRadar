import PRRadarConfigService

public struct LoadSettingsUseCase: Sendable {

    private let settingsService: SettingsService

    public init(settingsService: SettingsService) {
        self.settingsService = settingsService
    }

    public func execute() -> AppSettings {
        settingsService.load()
    }
}
