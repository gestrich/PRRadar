import Foundation
import PRRadarConfigService

public struct LoadCredentialStatusUseCase: Sendable {

    private let settingsService: SettingsService

    public init(settingsService: SettingsService) {
        self.settingsService = settingsService
    }

    public func execute(account: String) -> CredentialStatus {
        let hasGitHub = (try? settingsService.loadGitHubToken(account: account)) != nil
        let hasAnthropic = (try? settingsService.loadAnthropicKey(account: account)) != nil
        return CredentialStatus(account: account, hasGitHubToken: hasGitHub, hasAnthropicKey: hasAnthropic)
    }
}
