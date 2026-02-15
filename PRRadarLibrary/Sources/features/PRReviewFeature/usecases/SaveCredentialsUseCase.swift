import Foundation
import PRRadarConfigService

public struct SaveCredentialsUseCase: Sendable {

    private let settingsService: SettingsService

    public init(settingsService: SettingsService) {
        self.settingsService = settingsService
    }

    public func execute(account: String, githubToken: String?, anthropicKey: String?) throws {
        if let githubToken, !githubToken.isEmpty {
            try settingsService.saveGitHubToken(githubToken, account: account)
        }
        if let anthropicKey, !anthropicKey.isEmpty {
            try settingsService.saveAnthropicKey(anthropicKey, account: account)
        }
    }
}
