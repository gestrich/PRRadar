import PRRadarConfigService

struct CredentialStatusLoader {
    private let settingsService: SettingsService

    init(settingsService: SettingsService) {
        self.settingsService = settingsService
    }

    func loadAllStatuses() throws -> [CredentialStatus] {
        try settingsService.listCredentialAccounts().map { account in
            loadStatus(account: account)
        }
    }

    func loadStatus(account: String) -> CredentialStatus {
        let gitHubAuth: GitHubAuthStatus
        switch settingsService.loadGitHubAuth(account: account) {
        case .token: gitHubAuth = .token
        case .app: gitHubAuth = .app
        case nil: gitHubAuth = .none
        }
        let hasAnthropic = (try? settingsService.loadAnthropicKey(account: account)) != nil
        return CredentialStatus(account: account, gitHubAuth: gitHubAuth, hasAnthropicKey: hasAnthropic)
    }
}
