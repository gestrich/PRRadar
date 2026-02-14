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

    private func makeService() -> SettingsService {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = dir.appendingPathComponent("settings.json")
        return SettingsService(settingsURL: fileURL, keychain: InMemoryKeychainStore())
    }

    // MARK: - GitHub Token

    @Test("Saves and loads GitHub token for named account")
    func saveAndLoadGitHubToken() throws {
        let service = makeService()

        try service.saveGitHubToken("ghp_abc123", account: "work")
        let loaded = try service.loadGitHubToken(account: "work")

        #expect(loaded == "ghp_abc123")
    }

    @Test("Loading GitHub token for unknown account throws")
    func loadGitHubTokenThrowsWhenMissing() {
        let service = makeService()

        #expect(throws: (any Error).self) {
            _ = try service.loadGitHubToken(account: "nonexistent")
        }
    }

    @Test("Removes GitHub token for account")
    func removeGitHubToken() throws {
        let service = makeService()
        try service.saveGitHubToken("ghp_abc123", account: "work")

        try service.removeGitHubToken(account: "work")

        #expect(throws: (any Error).self) {
            _ = try service.loadGitHubToken(account: "work")
        }
    }

    // MARK: - Anthropic API Key

    @Test("Saves and loads Anthropic key for named account")
    func saveAndLoadAnthropicKey() throws {
        let service = makeService()

        try service.saveAnthropicKey("sk-ant-xxx", account: "work")
        let loaded = try service.loadAnthropicKey(account: "work")

        #expect(loaded == "sk-ant-xxx")
    }

    @Test("Loading Anthropic key for unknown account throws")
    func loadAnthropicKeyThrowsWhenMissing() {
        let service = makeService()

        #expect(throws: (any Error).self) {
            _ = try service.loadAnthropicKey(account: "nonexistent")
        }
    }

    @Test("Removes Anthropic key for account")
    func removeAnthropicKey() throws {
        let service = makeService()
        try service.saveAnthropicKey("sk-ant-xxx", account: "work")

        try service.removeAnthropicKey(account: "work")

        #expect(throws: (any Error).self) {
            _ = try service.loadAnthropicKey(account: "work")
        }
    }

    // MARK: - Account Isolation

    @Test("Tokens are isolated between accounts")
    func tokensIsolatedBetweenAccounts() throws {
        let service = makeService()

        try service.saveGitHubToken("ghp_work", account: "work")
        try service.saveGitHubToken("ghp_personal", account: "personal")

        #expect(try service.loadGitHubToken(account: "work") == "ghp_work")
        #expect(try service.loadGitHubToken(account: "personal") == "ghp_personal")
    }

    // MARK: - Remove Credentials

    @Test("Removes both tokens for an account")
    func removeCredentialsRemovesBoth() throws {
        let service = makeService()
        try service.saveGitHubToken("ghp_xxx", account: "work")
        try service.saveAnthropicKey("sk-ant-xxx", account: "work")

        try service.removeCredentials(account: "work")

        #expect(throws: (any Error).self) {
            _ = try service.loadGitHubToken(account: "work")
        }
        #expect(throws: (any Error).self) {
            _ = try service.loadAnthropicKey(account: "work")
        }
    }

    @Test("Remove credentials does not affect other accounts")
    func removeCredentialsIsolated() throws {
        let service = makeService()
        try service.saveGitHubToken("ghp_work", account: "work")
        try service.saveGitHubToken("ghp_personal", account: "personal")

        try service.removeCredentials(account: "work")

        #expect(try service.loadGitHubToken(account: "personal") == "ghp_personal")
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
        try service.saveGitHubToken("ghp_work", account: "work")
        try service.saveAnthropicKey("sk-ant-personal", account: "personal")

        let accounts = try service.listCredentialAccounts()

        #expect(accounts == ["personal", "work"])
    }

    @Test("Account with both tokens appears once in list")
    func listAccountsDeduplicates() throws {
        let service = makeService()
        try service.saveGitHubToken("ghp_work", account: "work")
        try service.saveAnthropicKey("sk-ant-work", account: "work")

        let accounts = try service.listCredentialAccounts()

        #expect(accounts == ["work"])
    }

    @Test("List accounts returns empty when no credentials stored")
    func listAccountsEmpty() throws {
        let service = makeService()

        let accounts = try service.listCredentialAccounts()

        #expect(accounts.isEmpty)
    }

    @Test("List accounts returns sorted names")
    func listAccountsSorted() throws {
        let service = makeService()
        try service.saveGitHubToken("t1", account: "zebra")
        try service.saveGitHubToken("t2", account: "alpha")
        try service.saveGitHubToken("t3", account: "middle")

        let accounts = try service.listCredentialAccounts()

        #expect(accounts == ["alpha", "middle", "zebra"])
    }
}
