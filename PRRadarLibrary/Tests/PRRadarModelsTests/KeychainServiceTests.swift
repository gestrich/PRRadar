import Foundation
import KeychainSDK
import Testing
@testable import PRRadarConfigService

final class InMemoryKeychainStore: KeychainStoring, @unchecked Sendable {
    private var storage: [String: String] = [:]

    func setString(_ string: String, forKey key: String) throws {
        storage[key] = string
    }

    func string(forKey key: String) throws -> String {
        guard let value = storage[key] else {
            throw KeyNotFoundError(key: key)
        }
        return value
    }

    func removeObject(forKey key: String) throws {
        storage.removeValue(forKey: key)
    }

    func allKeys() throws -> Set<String> {
        Set(storage.keys)
    }
}

private struct KeyNotFoundError: Error {
    let key: String
}

@Suite("SettingsService Credentials")
struct SettingsServiceCredentialTests {

    private func makeService(keychain: InMemoryKeychainStore = InMemoryKeychainStore()) -> SettingsService {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = dir.appendingPathComponent("settings.json")
        return SettingsService(settingsURL: fileURL, keychain: keychain)
    }

    // MARK: - GitHub Auth: Token

    @Test("Saves and loads a GitHub token")
    func saveAndLoadToken() throws {
        // Arrange
        let service = makeService()

        // Act
        try service.saveGitHubAuth(.token("ghp_abc123"), account: "work")
        let auth = service.loadGitHubAuth(account: "work")

        // Assert
        guard case .token(let token) = auth else {
            Issue.record("Expected .token, got \(String(describing: auth))")
            return
        }
        #expect(token == "ghp_abc123")
    }

    @Test("Loading GitHub auth for unknown account returns nil")
    func loadGitHubAuthReturnsNilWhenMissing() {
        // Arrange
        let service = makeService()

        // Act / Assert
        #expect(service.loadGitHubAuth(account: "nonexistent") == nil)
    }

    // MARK: - GitHub Auth: App

    @Test("Saves and loads GitHub App credentials")
    func saveAndLoadApp() throws {
        // Arrange
        let service = makeService()

        // Act
        try service.saveGitHubAuth(.app(appId: "123", installationId: "456", privateKeyPEM: "PEM"), account: "work")
        let auth = service.loadGitHubAuth(account: "work")

        // Assert
        guard case .app(let appId, let installId, let pem) = auth else {
            Issue.record("Expected .app, got \(String(describing: auth))")
            return
        }
        #expect(appId == "123")
        #expect(installId == "456")
        #expect(pem == "PEM")
    }

    // MARK: - Mutual Exclusivity

    @Test("Saving a token clears app credentials")
    func tokenClearsApp() throws {
        // Arrange
        let service = makeService()
        try service.saveGitHubAuth(.app(appId: "1", installationId: "2", privateKeyPEM: "3"), account: "work")

        // Act
        try service.saveGitHubAuth(.token("ghp_new"), account: "work")
        let auth = service.loadGitHubAuth(account: "work")

        // Assert
        guard case .token(let token) = auth else {
            Issue.record("Expected .token after overwrite, got \(String(describing: auth))")
            return
        }
        #expect(token == "ghp_new")
    }

    @Test("Saving app credentials clears the token")
    func appClearsToken() throws {
        // Arrange
        let service = makeService()
        try service.saveGitHubAuth(.token("ghp_old"), account: "work")

        // Act
        try service.saveGitHubAuth(.app(appId: "1", installationId: "2", privateKeyPEM: "3"), account: "work")
        let auth = service.loadGitHubAuth(account: "work")

        // Assert
        guard case .app = auth else {
            Issue.record("Expected .app after overwrite, got \(String(describing: auth))")
            return
        }
    }

    // MARK: - Anthropic Key

    @Test("Saves and loads Anthropic key for named account")
    func saveAndLoadAnthropicKey() throws {
        let service = makeService()
        try service.saveAnthropicKey("sk-ant-xxx", account: "work")

        #expect(try service.loadAnthropicKey(account: "work") == "sk-ant-xxx")
    }

    @Test("Loading Anthropic key for unknown account throws")
    func loadAnthropicKeyThrowsWhenMissing() {
        let service = makeService()

        #expect(throws: (any Error).self) {
            _ = try service.loadAnthropicKey(account: "nonexistent")
        }
    }

    // MARK: - Account Isolation

    @Test("Tokens are isolated between accounts")
    func tokensIsolatedBetweenAccounts() throws {
        // Arrange
        let service = makeService()
        try service.saveGitHubAuth(.token("ghp_work"), account: "work")
        try service.saveGitHubAuth(.token("ghp_personal"), account: "personal")

        // Assert
        guard case .token(let workToken) = service.loadGitHubAuth(account: "work"),
              case .token(let personalToken) = service.loadGitHubAuth(account: "personal") else {
            Issue.record("Expected both accounts to have tokens")
            return
        }
        #expect(workToken == "ghp_work")
        #expect(personalToken == "ghp_personal")
    }

    // MARK: - Remove Credentials

    @Test("Removes all credentials for an account")
    func removeCredentialsRemovesAll() throws {
        // Arrange
        let service = makeService()
        try service.saveGitHubAuth(.token("ghp_xxx"), account: "work")
        try service.saveAnthropicKey("sk-ant-xxx", account: "work")

        // Act
        try service.removeCredentials(account: "work")

        // Assert
        #expect(service.loadGitHubAuth(account: "work") == nil)
        #expect(throws: (any Error).self) { _ = try service.loadAnthropicKey(account: "work") }
    }

    @Test("Remove credentials does not affect other accounts")
    func removeCredentialsIsolated() throws {
        // Arrange
        let service = makeService()
        try service.saveGitHubAuth(.token("ghp_work"), account: "work")
        try service.saveGitHubAuth(.token("ghp_personal"), account: "personal")

        // Act
        try service.removeCredentials(account: "work")

        // Assert
        guard case .token(let token) = service.loadGitHubAuth(account: "personal") else {
            Issue.record("Expected personal token to survive")
            return
        }
        #expect(token == "ghp_personal")
    }

    @Test("Remove credentials succeeds when account has no tokens")
    func removeCredentialsNoTokensDoesNotThrow() throws {
        let service = makeService()
        try service.removeCredentials(account: "empty")
    }

    // MARK: - List Accounts

    @Test("Lists accounts with stored credentials")
    func listAccountsReturnsStoredAccounts() throws {
        let service = makeService()
        try service.saveGitHubAuth(.token("ghp_work"), account: "work")
        try service.saveAnthropicKey("sk-ant-personal", account: "personal")

        let accounts = try service.listCredentialAccounts()

        #expect(accounts == ["personal", "work"])
    }

    @Test("Account with both token types appears once in list")
    func listAccountsDeduplicates() throws {
        let service = makeService()
        try service.saveGitHubAuth(.token("ghp_work"), account: "work")
        try service.saveAnthropicKey("sk-ant-work", account: "work")

        let accounts = try service.listCredentialAccounts()

        #expect(accounts == ["work"])
    }

    @Test("List accounts returns empty when no credentials stored")
    func listAccountsEmpty() throws {
        let service = makeService()
        #expect(try service.listCredentialAccounts().isEmpty)
    }

    @Test("List accounts returns sorted names")
    func listAccountsSorted() throws {
        let service = makeService()
        try service.saveGitHubAuth(.token("t1"), account: "zebra")
        try service.saveGitHubAuth(.token("t2"), account: "alpha")
        try service.saveGitHubAuth(.token("t3"), account: "middle")

        let accounts = try service.listCredentialAccounts()

        #expect(accounts == ["alpha", "middle", "zebra"])
    }

    @Test("App credential account appears in list")
    func appCredentialAccountInList() throws {
        let service = makeService()
        try service.saveGitHubAuth(.app(appId: "1", installationId: "2", privateKeyPEM: "3"), account: "bot")

        let accounts = try service.listCredentialAccounts()

        #expect(accounts.contains("bot"))
    }
}
