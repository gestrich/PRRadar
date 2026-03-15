import Foundation
import PRRadarConfigService

public struct RemoveCredentialsUseCase: Sendable {

    private let settingsService: SettingsService

    public init(settingsService: SettingsService) {
        self.settingsService = settingsService
    }

    @discardableResult
    public func execute(account: String) throws -> [CredentialStatus] {
        try settingsService.removeCredentials(account: account)
        return try CredentialStatusLoader(settingsService: settingsService).loadAllStatuses()
    }
}
