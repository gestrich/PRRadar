import Foundation
import KeychainSDK
import Testing
@testable import PRRadarConfigService

@Suite("CredentialResolver")
struct CredentialResolverTests {

    private func makeSettingsService(keychain: InMemoryKeychainStore = InMemoryKeychainStore()) -> SettingsService {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = dir.appendingPathComponent("settings.json")
        return SettingsService(settingsURL: fileURL, keychain: keychain)
    }

    // MARK: - GitHub Token Resolution Order

    @Test("GitHub token resolves from process environment first")
    func gitHubTokenFromProcessEnv() {
        // Arrange
        let resolver = CredentialResolver(
            settingsService: makeSettingsService(),
            processEnvironment: ["GITHUB_TOKEN": "from-process-env"],
            dotEnv: ["GITHUB_TOKEN": "from-dotenv"]
        )

        // Act
        let token = resolver.getGitHubToken()

        // Assert
        #expect(token == "from-process-env")
    }

    @Test("GitHub token falls back to .env when process env is empty")
    func gitHubTokenFromDotEnv() {
        // Arrange
        let resolver = CredentialResolver(
            settingsService: makeSettingsService(),
            processEnvironment: [:],
            dotEnv: ["GITHUB_TOKEN": "from-dotenv"]
        )

        // Act
        let token = resolver.getGitHubToken()

        // Assert
        #expect(token == "from-dotenv")
    }

    @Test("GitHub token falls back to keychain when env sources are empty")
    func gitHubTokenFromKeychain() throws {
        // Arrange
        let keychain = InMemoryKeychainStore()
        let service = makeSettingsService(keychain: keychain)
        try service.saveGitHubToken("from-keychain", account: "default")
        let resolver = CredentialResolver(
            settingsService: service,
            processEnvironment: [:],
            dotEnv: [:]
        )

        // Act
        let token = resolver.getGitHubToken()

        // Assert
        #expect(token == "from-keychain")
    }

    @Test(".env takes precedence over keychain for GitHub token")
    func gitHubTokenDotEnvBeatsKeychain() throws {
        // Arrange
        let keychain = InMemoryKeychainStore()
        let service = makeSettingsService(keychain: keychain)
        try service.saveGitHubToken("from-keychain", account: "default")
        let resolver = CredentialResolver(
            settingsService: service,
            processEnvironment: [:],
            dotEnv: ["GITHUB_TOKEN": "from-dotenv"]
        )

        // Act
        let token = resolver.getGitHubToken()

        // Assert
        #expect(token == "from-dotenv")
    }

    @Test("GitHub token returns nil when no source has a value")
    func gitHubTokenReturnsNilWhenMissing() {
        // Arrange
        let resolver = CredentialResolver(
            settingsService: makeSettingsService(),
            processEnvironment: [:],
            dotEnv: [:]
        )

        // Act
        let token = resolver.getGitHubToken()

        // Assert
        #expect(token == nil)
    }

    // MARK: - GitHub Token Account Selection

    @Test("GitHub token uses configured account for keychain lookup")
    func gitHubTokenUsesConfiguredAccount() throws {
        // Arrange
        let keychain = InMemoryKeychainStore()
        let service = makeSettingsService(keychain: keychain)
        try service.saveGitHubToken("work-token", account: "work")
        let resolver = CredentialResolver(
            settingsService: service,
            githubAccount: "work",
            processEnvironment: [:],
            dotEnv: [:]
        )

        // Act
        let token = resolver.getGitHubToken()

        // Assert
        #expect(token == "work-token")
    }

    @Test("GitHub token uses default account when no account configured")
    func gitHubTokenUsesDefaultAccount() throws {
        // Arrange
        let keychain = InMemoryKeychainStore()
        let service = makeSettingsService(keychain: keychain)
        try service.saveGitHubToken("default-token", account: "default")
        let resolver = CredentialResolver(
            settingsService: service,
            githubAccount: nil,
            processEnvironment: [:],
            dotEnv: [:]
        )

        // Act
        let token = resolver.getGitHubToken()

        // Assert
        #expect(token == "default-token")
    }

    @Test("GitHub token uses default account when configured account is empty string")
    func gitHubTokenDefaultsOnEmptyAccount() throws {
        // Arrange
        let keychain = InMemoryKeychainStore()
        let service = makeSettingsService(keychain: keychain)
        try service.saveGitHubToken("default-token", account: "default")
        let resolver = CredentialResolver(
            settingsService: service,
            githubAccount: "",
            processEnvironment: [:],
            dotEnv: [:]
        )

        // Act
        let token = resolver.getGitHubToken()

        // Assert
        #expect(token == "default-token")
    }

    // MARK: - Anthropic Key Resolution Order

    @Test("Anthropic key resolves from process environment first")
    func anthropicKeyFromProcessEnv() {
        // Arrange
        let resolver = CredentialResolver(
            settingsService: makeSettingsService(),
            processEnvironment: ["ANTHROPIC_API_KEY": "from-process-env"],
            dotEnv: ["ANTHROPIC_API_KEY": "from-dotenv"]
        )

        // Act
        let key = resolver.getAnthropicKey()

        // Assert
        #expect(key == "from-process-env")
    }

    @Test("Anthropic key falls back to .env when process env is empty")
    func anthropicKeyFromDotEnv() {
        // Arrange
        let resolver = CredentialResolver(
            settingsService: makeSettingsService(),
            processEnvironment: [:],
            dotEnv: ["ANTHROPIC_API_KEY": "from-dotenv"]
        )

        // Act
        let key = resolver.getAnthropicKey()

        // Assert
        #expect(key == "from-dotenv")
    }

    @Test("Anthropic key falls back to keychain when env sources are empty")
    func anthropicKeyFromKeychain() throws {
        // Arrange
        let keychain = InMemoryKeychainStore()
        let service = makeSettingsService(keychain: keychain)
        try service.saveAnthropicKey("from-keychain", account: "default")
        let resolver = CredentialResolver(
            settingsService: service,
            processEnvironment: [:],
            dotEnv: [:]
        )

        // Act
        let key = resolver.getAnthropicKey()

        // Assert
        #expect(key == "from-keychain")
    }

    @Test("Anthropic key returns nil when no source has a value")
    func anthropicKeyReturnsNilWhenMissing() {
        // Arrange
        let resolver = CredentialResolver(
            settingsService: makeSettingsService(),
            processEnvironment: [:],
            dotEnv: [:]
        )

        // Act
        let key = resolver.getAnthropicKey()

        // Assert
        #expect(key == nil)
    }

    // MARK: - Anthropic Key Always Uses Default Account

    @Test("Anthropic key always uses default account regardless of configured account")
    func anthropicKeyIgnoresConfiguredAccount() throws {
        // Arrange
        let keychain = InMemoryKeychainStore()
        let service = makeSettingsService(keychain: keychain)
        try service.saveAnthropicKey("default-key", account: "default")
        let resolver = CredentialResolver(
            settingsService: service,
            githubAccount: "work",
            processEnvironment: [:],
            dotEnv: [:]
        )

        // Act
        let key = resolver.getAnthropicKey()

        // Assert
        #expect(key == "default-key")
    }

    // MARK: - Combined Resolution

    @Test("Resolves GitHub token from configured account and Anthropic key from default simultaneously")
    func combinedResolution() throws {
        // Arrange
        let keychain = InMemoryKeychainStore()
        let service = makeSettingsService(keychain: keychain)
        try service.saveGitHubToken("work-gh-token", account: "work")
        try service.saveAnthropicKey("default-anthropic-key", account: "default")
        let resolver = CredentialResolver(
            settingsService: service,
            githubAccount: "work",
            processEnvironment: [:],
            dotEnv: [:]
        )

        // Act
        let ghToken = resolver.getGitHubToken()
        let anthropicKey = resolver.getAnthropicKey()

        // Assert
        #expect(ghToken == "work-gh-token")
        #expect(anthropicKey == "default-anthropic-key")
    }

    @Test("Mixed sources: GitHub from .env, Anthropic from keychain")
    func mixedSources() throws {
        // Arrange
        let keychain = InMemoryKeychainStore()
        let service = makeSettingsService(keychain: keychain)
        try service.saveAnthropicKey("keychain-anthropic", account: "default")
        let resolver = CredentialResolver(
            settingsService: service,
            processEnvironment: [:],
            dotEnv: ["GITHUB_TOKEN": "dotenv-gh-token"]
        )

        // Act
        let ghToken = resolver.getGitHubToken()
        let anthropicKey = resolver.getAnthropicKey()

        // Assert
        #expect(ghToken == "dotenv-gh-token")
        #expect(anthropicKey == "keychain-anthropic")
    }
}
