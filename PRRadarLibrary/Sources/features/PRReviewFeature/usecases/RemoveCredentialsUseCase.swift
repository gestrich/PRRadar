import Foundation
import PRRadarConfigService

public struct RemoveCredentialsUseCase: Sendable {

    private let settingsService: SettingsService

    public init(settingsService: SettingsService) {
        self.settingsService = settingsService
    }

    public func execute(account: String) throws {
        try settingsService.removeCredentials(account: account)
    }
}
