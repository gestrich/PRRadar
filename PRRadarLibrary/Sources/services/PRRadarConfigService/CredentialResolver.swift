import Foundation

public struct CredentialResolver: Sendable {
    private let settingsService: SettingsService
    private let environment: [String: String]
    private let credentialAccount: String?

    public init(settingsService: SettingsService, credentialAccount: String? = nil, environment: [String: String]? = nil) {
        self.settingsService = settingsService
        self.credentialAccount = credentialAccount
        self.environment = environment ?? PRRadarEnvironment.build(credentialAccount: credentialAccount)
    }

    public func resolveGitHubToken() -> String? {
        if let envToken = environment[PRRadarEnvironment.githubTokenKey] {
            return envToken
        }
        return loadFromKeychain { account in
            try settingsService.loadGitHubToken(account: account)
        }
    }

    public func resolveAnthropicKey() -> String? {
        if let envKey = environment[PRRadarEnvironment.anthropicAPIKeyKey] {
            return envKey
        }
        return loadFromKeychain { account in
            try settingsService.loadAnthropicKey(account: account)
        }
    }

    private func loadFromKeychain(loader: (String) throws -> String) -> String? {
        let account = (credentialAccount?.isEmpty ?? true) ? PRRadarEnvironment.defaultCredentialAccount : credentialAccount!
        return try? loader(account)
    }
}
