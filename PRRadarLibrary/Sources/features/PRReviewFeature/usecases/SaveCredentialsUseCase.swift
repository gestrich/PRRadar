import Foundation
import PRRadarConfigService

public struct SaveCredentialsUseCase: Sendable {

    private let settingsService: SettingsService

    public init(settingsService: SettingsService) {
        self.settingsService = settingsService
    }

    @discardableResult
    public func execute(
        account: String,
        gitHubAuth: GitHubAuth?,
        anthropicKey: String?
    ) throws -> [CredentialStatus] {
        if let gitHubAuth {
            try settingsService.saveGitHubAuth(gitHubAuth, account: account)
        }
        if let anthropicKey, !anthropicKey.isEmpty {
            try settingsService.saveAnthropicKey(anthropicKey, account: account)
        }
        return try CredentialStatusLoader(settingsService: settingsService).loadAllStatuses()
    }
}
