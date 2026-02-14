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
        // TODO: We are also doing enviroment things with these same stirngs in 
        // PRRadarEnvironment. This seems sketchy
        if let envToken = environment["GITHUB_TOKEN"] {
            return envToken
        }
        return loadFromKeychain { account in
            try settingsService.loadGitHubToken(account: account)
        }
    }

    public func resolveAnthropicKey() -> String? {
        if let envKey = environment["ANTHROPIC_API_KEY"] {
            return envKey
        }
        return loadFromKeychain { account in
            try settingsService.loadAnthropicKey(account: account)
        }
    }

    private func loadFromKeychain(loader: (String) throws -> String) -> String? {
        // TODO:
        // Need to resaearch if an empty credentialAccount is normla
        // fallbacks like "default" are uncealr why they exists and what happens
        let account = (credentialAccount?.isEmpty ?? true) ? "default" : credentialAccount!
        return try? loader(account)
    }
}
