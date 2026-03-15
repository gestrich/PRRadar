import Foundation
import PRRadarConfigService

public struct LoadCredentialStatusUseCase: Sendable {

    private let settingsService: SettingsService

    public init(settingsService: SettingsService) {
        self.settingsService = settingsService
    }

    public func execute(account: String) -> CredentialStatus {
        CredentialStatusLoader(settingsService: settingsService).loadStatus(account: account)
    }
}
