import Foundation

public struct CredentialResolver: Sendable {
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
        self.dotEnv = dotEnv ?? PRRadarEnvironment.loadDotEnv()
    }

    public func getGitHubToken() -> String? {
        let envKey = PRRadarEnvironment.githubTokenKey
        let keychainType = SettingsService.gitHubTokenType
        let account = (credentialAccount?.isEmpty ?? true)
            ? PRRadarEnvironment.defaultCredentialAccount
            : credentialAccount!

        if let v = processEnvironment[envKey] { return v }
        if let v = dotEnv[envKey] { return v }
        return try? settingsService.loadCredential(account: account, type: keychainType)
    }

    public func getAnthropicKey() -> String? {
        let envKey = PRRadarEnvironment.anthropicAPIKeyKey
        let keychainType = SettingsService.anthropicKeyType

        if let v = processEnvironment[envKey] { return v }
        if let v = dotEnv[envKey] { return v }
        return try? settingsService.loadCredential(
            account: PRRadarEnvironment.defaultCredentialAccount,
            type: keychainType
        )
    }
}
