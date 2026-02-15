import Foundation
import PRRadarConfigService

public struct SaveCredentialsUseCase: Sendable {

    private let settingsService: SettingsService

    public init(settingsService: SettingsService) {
        self.settingsService = settingsService
    }

    @discardableResult
    public func execute(account: String, githubToken: String?, anthropicKey: String?) throws -> [CredentialStatus] {
        if let githubToken, !githubToken.isEmpty {
            try settingsService.saveGitHubToken(githubToken, account: account)
        }
        if let anthropicKey, !anthropicKey.isEmpty {
            try settingsService.saveAnthropicKey(anthropicKey, account: account)
        }
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
