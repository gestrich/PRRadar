import Foundation
import PRRadarConfigService

public struct ListCredentialAccountsUseCase: Sendable {

    private let settingsService: SettingsService

    public init(settingsService: SettingsService) {
        self.settingsService = settingsService
    }

    public func execute() throws -> [String] {
        try settingsService.listCredentialAccounts()
    }
}
