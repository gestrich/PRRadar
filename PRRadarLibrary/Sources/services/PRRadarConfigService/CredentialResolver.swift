import EnvironmentSDK
import Foundation

public struct CredentialResolver: Sendable {
    public static let githubTokenKey = "GITHUB_TOKEN"
    public static let anthropicAPIKeyKey = "ANTHROPIC_API_KEY"

    private let processEnvironment: [String: String]
    private let dotEnv: [String: String]
    private let settingsService: SettingsService
    private let account: String

    public init(
        settingsService: SettingsService,
        githubAccount: String,
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        dotEnv: [String: String]? = nil
    ) {
        self.settingsService = settingsService
        self.account = githubAccount
        self.processEnvironment = processEnvironment
        self.dotEnv = dotEnv ?? DotEnvironmentLoader.loadDotEnv()
    }

    public func getGitHubToken() -> String? {
        if let v = processEnvironment[Self.githubTokenKey] { return v }
        if let v = dotEnv[Self.githubTokenKey] { return v }
        return try? settingsService.loadCredential(account: account, type: SettingsService.gitHubTokenType)
    }

    public func getAnthropicKey() -> String? {
        if let v = processEnvironment[Self.anthropicAPIKeyKey] { return v }
        if let v = dotEnv[Self.anthropicAPIKeyKey] { return v }
        return try? settingsService.loadCredential(account: account, type: SettingsService.anthropicKeyType)
    }
}
