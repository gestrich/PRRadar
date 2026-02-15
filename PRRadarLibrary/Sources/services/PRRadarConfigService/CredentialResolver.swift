import EnvironmentSDK
import Foundation

public struct CredentialResolver: Sendable {
    public static let githubTokenKey = "GITHUB_TOKEN"
    public static let anthropicAPIKeyKey = "ANTHROPIC_API_KEY"
    /// Repos with no `credentialAccount` use this as the Keychain lookup key.
    /// Lets single-credential users skip account configuration entirely.
    public static let defaultCredentialAccount = "default"

    private let processEnvironment: [String: String]
    private let dotEnv: [String: String]
    private let settingsService: SettingsService
    private let credentialAccount: String?

    public init(
        settingsService: SettingsService,
        credentialAccount: String? = nil,
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        dotEnv: [String: String]? = nil
    ) {
        self.settingsService = settingsService
        self.credentialAccount = credentialAccount
        self.processEnvironment = processEnvironment
        self.dotEnv = dotEnv ?? DotEnvironmentLoader.loadDotEnv()
    }

    public func getGitHubToken() -> String? {
        let envKey = Self.githubTokenKey
        let keychainType = SettingsService.gitHubTokenType
        let account = (credentialAccount?.isEmpty ?? true)
            ? Self.defaultCredentialAccount
            : credentialAccount!

        if let v = processEnvironment[envKey] { return v }
        if let v = dotEnv[envKey] { return v }
        return try? settingsService.loadCredential(account: account, type: keychainType)
    }

    public func getAnthropicKey() -> String? {
        let envKey = Self.anthropicAPIKeyKey
        let keychainType = SettingsService.anthropicKeyType

        if let v = processEnvironment[envKey] { return v }
        if let v = dotEnv[envKey] { return v }
        return try? settingsService.loadCredential(
            account: Self.defaultCredentialAccount,
            type: keychainType
        )
    }
}
