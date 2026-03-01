import Foundation
import KeychainSDK
import Testing

@Suite("EnvironmentKeychainStore")
struct EnvironmentKeychainStoreTests {

    // MARK: - Reading

    @Test("Reads GitHub token from GITHUB_TOKEN env var")
    func readsGitHubToken() throws {
        let store = EnvironmentKeychainStore(environment: ["GITHUB_TOKEN": "ghp_abc123"])

        let value = try store.string(forKey: "work/github-token")

        #expect(value == "ghp_abc123")
    }

    @Test("Reads Anthropic key from ANTHROPIC_API_KEY env var")
    func readsAnthropicKey() throws {
        let store = EnvironmentKeychainStore(environment: ["ANTHROPIC_API_KEY": "sk-ant-xxx"])

        let value = try store.string(forKey: "myaccount/anthropic-api-key")

        #expect(value == "sk-ant-xxx")
    }

    @Test("Account portion of key is ignored")
    func accountIsIgnored() throws {
        let store = EnvironmentKeychainStore(environment: ["GITHUB_TOKEN": "ghp_123"])

        let fromWork = try store.string(forKey: "work/github-token")
        let fromPersonal = try store.string(forKey: "personal/github-token")

        #expect(fromWork == fromPersonal)
    }

    @Test("Throws itemNotFound when env var is missing")
    func throwsWhenMissing() {
        let store = EnvironmentKeychainStore(environment: [:])

        #expect(throws: KeychainStoreError.self) {
            _ = try store.string(forKey: "work/github-token")
        }
    }

    @Test("Throws itemNotFound when env var is empty string")
    func throwsWhenEmpty() {
        let store = EnvironmentKeychainStore(environment: ["GITHUB_TOKEN": ""])

        #expect(throws: KeychainStoreError.self) {
            _ = try store.string(forKey: "work/github-token")
        }
    }

    @Test("Throws itemNotFound for unknown key type")
    func throwsForUnknownType() {
        let store = EnvironmentKeychainStore(environment: ["GITHUB_TOKEN": "ghp_123"])

        #expect(throws: KeychainStoreError.self) {
            _ = try store.string(forKey: "work/unknown-type")
        }
    }

    // MARK: - Write operations

    @Test("setString throws readOnly")
    func setStringThrows() {
        let store = EnvironmentKeychainStore(environment: [:])

        #expect(throws: KeychainStoreError.self) {
            try store.setString("value", forKey: "work/github-token")
        }
    }

    @Test("removeObject throws readOnly")
    func removeObjectThrows() {
        let store = EnvironmentKeychainStore(environment: [:])

        #expect(throws: KeychainStoreError.self) {
            try store.removeObject(forKey: "work/github-token")
        }
    }

    // MARK: - allKeys

    @Test("allKeys returns keys for set env vars")
    func allKeysReturnsSetVars() throws {
        let store = EnvironmentKeychainStore(environment: [
            "GITHUB_TOKEN": "ghp_123",
            "ANTHROPIC_API_KEY": "sk-ant-xxx",
        ])

        let keys = try store.allKeys()

        #expect(keys == Set(["env/github-token", "env/anthropic-api-key"]))
    }

    @Test("allKeys excludes empty env vars")
    func allKeysExcludesEmpty() throws {
        let store = EnvironmentKeychainStore(environment: [
            "GITHUB_TOKEN": "ghp_123",
            "ANTHROPIC_API_KEY": "",
        ])

        let keys = try store.allKeys()

        #expect(keys == Set(["env/github-token"]))
    }

    @Test("allKeys returns empty when no env vars set")
    func allKeysEmpty() throws {
        let store = EnvironmentKeychainStore(environment: [:])

        let keys = try store.allKeys()

        #expect(keys.isEmpty)
    }
}
