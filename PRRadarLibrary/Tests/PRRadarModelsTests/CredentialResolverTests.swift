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

    // MARK: - GitHub Auth: Token Resolution

    @Test("GitHub token resolves from process environment first")
    func gitHubTokenFromProcessEnv() {
        // Arrange
        let resolver = CredentialResolver(
            settingsService: makeSettingsService(),
            githubAccount: "work",
            processEnvironment: ["GITHUB_TOKEN": "from-process-env"],
            dotEnv: ["GITHUB_TOKEN": "from-dotenv"]
        )

        // Act
        let auth = resolver.getGitHubAuth()

        // Assert
        guard case .token(let token) = auth else {
            Issue.record("Expected .token, got \(String(describing: auth))")
            return
        }
        #expect(token == "from-process-env")
    }

    @Test("GitHub token falls back to .env when process env is empty")
    func gitHubTokenFromDotEnv() {
        // Arrange
        let resolver = CredentialResolver(
            settingsService: makeSettingsService(),
            githubAccount: "work",
            processEnvironment: [:],
            dotEnv: ["GITHUB_TOKEN": "from-dotenv"]
        )

        // Act
        let auth = resolver.getGitHubAuth()

        // Assert
        guard case .token(let token) = auth else {
            Issue.record("Expected .token, got \(String(describing: auth))")
            return
        }
        #expect(token == "from-dotenv")
    }

    @Test("GitHub token falls back to keychain when env sources are empty")
    func gitHubTokenFromKeychain() throws {
        // Arrange
        let keychain = InMemoryKeychainStore()
        let service = makeSettingsService(keychain: keychain)
        try service.saveGitHubAuth(.token("from-keychain"), account: "work")
        let resolver = CredentialResolver(
            settingsService: service,
            githubAccount: "work",
            processEnvironment: [:],
            dotEnv: [:]
        )

        // Act
        let auth = resolver.getGitHubAuth()

        // Assert
        guard case .token(let token) = auth else {
            Issue.record("Expected .token, got \(String(describing: auth))")
            return
        }
        #expect(token == "from-keychain")
    }

    @Test(".env takes precedence over keychain for GitHub token")
    func gitHubTokenDotEnvBeatsKeychain() throws {
        // Arrange
        let keychain = InMemoryKeychainStore()
        let service = makeSettingsService(keychain: keychain)
        try service.saveGitHubAuth(.token("from-keychain"), account: "work")
        let resolver = CredentialResolver(
            settingsService: service,
            githubAccount: "work",
            processEnvironment: [:],
            dotEnv: ["GITHUB_TOKEN": "from-dotenv"]
        )

        // Act
        let auth = resolver.getGitHubAuth()

        // Assert
        guard case .token(let token) = auth else {
            Issue.record("Expected .token, got \(String(describing: auth))")
            return
        }
        #expect(token == "from-dotenv")
    }

    @Test("GitHub auth returns nil when no source has a value")
    func gitHubAuthReturnsNilWhenMissing() {
        // Arrange
        let resolver = CredentialResolver(
            settingsService: makeSettingsService(),
            githubAccount: "work",
            processEnvironment: [:],
            dotEnv: [:]
        )

        // Act
        let auth = resolver.getGitHubAuth()

        // Assert
        #expect(auth == nil)
    }

    @Test("GitHub token uses configured account for keychain lookup")
    func gitHubTokenUsesConfiguredAccount() throws {
        // Arrange
        let keychain = InMemoryKeychainStore()
        let service = makeSettingsService(keychain: keychain)
        try service.saveGitHubAuth(.token("work-token"), account: "work")
        let resolver = CredentialResolver(
            settingsService: service,
            githubAccount: "work",
            processEnvironment: [:],
            dotEnv: [:]
        )

        // Act
        let auth = resolver.getGitHubAuth()

        // Assert
        guard case .token(let token) = auth else {
            Issue.record("Expected .token, got \(String(describing: auth))")
            return
        }
        #expect(token == "work-token")
    }

    // MARK: - Anthropic Key Resolution

    @Test("Anthropic key resolves from process environment first")
    func anthropicKeyFromProcessEnv() {
        // Arrange
        let resolver = CredentialResolver(
            settingsService: makeSettingsService(),
            githubAccount: "work",
            processEnvironment: ["ANTHROPIC_API_KEY": "from-process-env"],
            dotEnv: ["ANTHROPIC_API_KEY": "from-dotenv"]
        )

        // Act / Assert
        #expect(resolver.getAnthropicKey() == "from-process-env")
    }

    @Test("Anthropic key falls back to .env when process env is empty")
    func anthropicKeyFromDotEnv() {
        // Arrange
        let resolver = CredentialResolver(
            settingsService: makeSettingsService(),
            githubAccount: "work",
            processEnvironment: [:],
            dotEnv: ["ANTHROPIC_API_KEY": "from-dotenv"]
        )

        // Act / Assert
        #expect(resolver.getAnthropicKey() == "from-dotenv")
    }

    @Test("Anthropic key falls back to keychain when env sources are empty")
    func anthropicKeyFromKeychain() throws {
        // Arrange
        let keychain = InMemoryKeychainStore()
        let service = makeSettingsService(keychain: keychain)
        try service.saveAnthropicKey("from-keychain", account: "work")
        let resolver = CredentialResolver(
            settingsService: service,
            githubAccount: "work",
            processEnvironment: [:],
            dotEnv: [:]
        )

        // Act / Assert
        #expect(resolver.getAnthropicKey() == "from-keychain")
    }

    @Test("Anthropic key returns nil when no source has a value")
    func anthropicKeyReturnsNilWhenMissing() {
        // Arrange
        let resolver = CredentialResolver(
            settingsService: makeSettingsService(),
            githubAccount: "work",
            processEnvironment: [:],
            dotEnv: [:]
        )

        // Act / Assert
        #expect(resolver.getAnthropicKey() == nil)
    }

    // MARK: - GitHub App Credentials

    @Test("App credentials return nil when nothing is configured")
    func appCredentialsNilWhenMissing() {
        // Arrange
        let resolver = CredentialResolver(
            settingsService: makeSettingsService(),
            githubAccount: "work",
            processEnvironment: [:],
            dotEnv: [:]
        )

        // Act / Assert
        #expect(resolver.getGitHubAuth() == nil)
    }

    @Test("App credentials resolve from keychain")
    func appCredentialsFromKeychain() throws {
        // Arrange
        let keychain = InMemoryKeychainStore()
        let service = makeSettingsService(keychain: keychain)
        try service.saveGitHubAuth(.app(appId: "app-123", installationId: "install-456", privateKeyPEM: "PEM"), account: "work")
        let resolver = CredentialResolver(
            settingsService: service,
            githubAccount: "work",
            processEnvironment: [:],
            dotEnv: [:]
        )

        // Act
        let auth = resolver.getGitHubAuth()

        // Assert
        guard case .app(let appId, let installId, let pem) = auth else {
            Issue.record("Expected .app, got \(String(describing: auth))")
            return
        }
        #expect(appId == "app-123")
        #expect(installId == "install-456")
        #expect(pem == "PEM")
    }

    @Test("App credentials resolve from environment variables")
    func appCredentialsFromEnv() {
        // Arrange
        let resolver = CredentialResolver(
            settingsService: makeSettingsService(),
            githubAccount: "work",
            processEnvironment: [
                "GITHUB_APP_ID": "env-app-id",
                "GITHUB_APP_INSTALLATION_ID": "env-install-id",
                "GITHUB_APP_PRIVATE_KEY": "env-pem",
            ],
            dotEnv: [:]
        )

        // Act
        let auth = resolver.getGitHubAuth()

        // Assert
        guard case .app(let appId, let installId, let pem) = auth else {
            Issue.record("Expected .app, got \(String(describing: auth))")
            return
        }
        #expect(appId == "env-app-id")
        #expect(installId == "env-install-id")
        #expect(pem == "env-pem")
    }

    @Test("App credentials take precedence over PAT")
    func appPrecedenceOverToken() throws {
        // Arrange
        let keychain = InMemoryKeychainStore()
        let service = makeSettingsService(keychain: keychain)
        // Manually store both (bypassing mutual exclusivity enforcement)
        try keychain.setString("my-pat", forKey: "work/github-token")
        try keychain.setString("app-1", forKey: "work/github-app-id")
        try keychain.setString("inst-1", forKey: "work/github-app-installation-id")
        try keychain.setString("pem-1", forKey: "work/github-app-private-key")
        let resolver = CredentialResolver(
            settingsService: service,
            githubAccount: "work",
            processEnvironment: [:],
            dotEnv: [:]
        )

        // Act
        let auth = resolver.getGitHubAuth()

        // Assert
        guard case .app = auth else {
            Issue.record("Expected .app to take precedence, got \(String(describing: auth))")
            return
        }
    }

    @Test("App credentials from env take precedence over PAT from env")
    func appEnvPrecedenceOverTokenEnv() {
        // Arrange
        let resolver = CredentialResolver(
            settingsService: makeSettingsService(),
            githubAccount: "work",
            processEnvironment: [
                "GITHUB_TOKEN": "my-pat",
                "GITHUB_APP_ID": "env-id",
                "GITHUB_APP_INSTALLATION_ID": "env-install",
                "GITHUB_APP_PRIVATE_KEY": "env-pem",
            ],
            dotEnv: [:]
        )

        // Act
        let auth = resolver.getGitHubAuth()

        // Assert
        guard case .app = auth else {
            Issue.record("Expected .app to take precedence, got \(String(describing: auth))")
            return
        }
    }
}
