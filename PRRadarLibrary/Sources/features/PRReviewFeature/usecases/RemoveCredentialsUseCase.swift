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
        return try loadAllStatuses()
    }

    private func loadAllStatuses() throws -> [CredentialStatus] {
        try settingsService.listCredentialAccounts().map { account in
            let hasGitHub = (try? settingsService.loadGitHubToken(account: account)) != nil
            let hasAnthropic = (try? settingsService.loadAnthropicKey(account: account)) != nil
            return CredentialStatus(account: account, hasGitHubToken: hasGitHub, hasAnthropicKey: hasAnthropic)
        }
    }
}
