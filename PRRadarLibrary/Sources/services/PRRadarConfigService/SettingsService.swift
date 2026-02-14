import Foundation
import KeychainSDK

public final class SettingsService: Sendable {
    private static let gitHubTokenType = "github-token"
    private static let anthropicKeyType = "anthropic-api-key"

    private let settingsURL: URL
    private let keychain: KeychainStoring

    public init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("PRRadar")
        self.settingsURL = appSupport.appendingPathComponent("settings.json")
        self.keychain = ValetKeychainStore(identifier: "com.gestrich.PRRadar")
    }

    public init(settingsURL: URL, keychain: KeychainStoring? = nil) {
        self.settingsURL = settingsURL
        self.keychain = keychain ?? ValetKeychainStore(identifier: "com.gestrich.PRRadar")
    }

    public func load() -> AppSettings {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else {
            return AppSettings()
        }
        do {
            let data = try Data(contentsOf: settingsURL)
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            return AppSettings()
        }
    }

    public func save(_ settings: AppSettings) throws {
        let directory = settingsURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: settingsURL)
    }

    public func addConfiguration(_ config: RepoConfiguration, to settings: inout AppSettings) {
        var config = config
        if settings.configurations.isEmpty {
            config.isDefault = true
        }
        settings.configurations.append(config)
    }

    public func removeConfiguration(id: UUID, from settings: inout AppSettings) {
        let wasDefault = settings.configurations.first(where: { $0.id == id })?.isDefault ?? false
        settings.configurations.removeAll(where: { $0.id == id })
        if wasDefault, let first = settings.configurations.first {
            let idx = settings.configurations.firstIndex(of: first)!
            settings.configurations[idx].isDefault = true
        }
    }

    public func setDefault(id: UUID, in settings: inout AppSettings) {
        for i in settings.configurations.indices {
            settings.configurations[i].isDefault = (settings.configurations[i].id == id)
        }
    }

    // MARK: - Credentials (Keychain)

    public func saveGitHubToken(_ token: String, account: String) throws {
        try keychain.setString(token, forKey: credentialKey(account: account, type: Self.gitHubTokenType))
    }

    public func loadGitHubToken(account: String) throws -> String {
        try keychain.string(forKey: credentialKey(account: account, type: Self.gitHubTokenType))
    }

    public func removeGitHubToken(account: String) throws {
        try keychain.removeObject(forKey: credentialKey(account: account, type: Self.gitHubTokenType))
    }

    public func saveAnthropicKey(_ apiKey: String, account: String) throws {
        try keychain.setString(apiKey, forKey: credentialKey(account: account, type: Self.anthropicKeyType))
    }

    public func loadAnthropicKey(account: String) throws -> String {
        try keychain.string(forKey: credentialKey(account: account, type: Self.anthropicKeyType))
    }

    public func removeAnthropicKey(account: String) throws {
        try keychain.removeObject(forKey: credentialKey(account: account, type: Self.anthropicKeyType))
    }

    public func removeCredentials(account: String) throws {
        try? keychain.removeObject(forKey: credentialKey(account: account, type: Self.gitHubTokenType))
        try? keychain.removeObject(forKey: credentialKey(account: account, type: Self.anthropicKeyType))
    }

    public func listCredentialAccounts() throws -> [String] {
        let keys = try keychain.allKeys()
        let accounts = Set(keys.compactMap { key -> String? in
            guard let slashIndex = key.firstIndex(of: "/") else { return nil }
            return String(key[key.startIndex..<slashIndex])
        })
        return accounts.sorted()
    }

    private func credentialKey(account: String, type: String) -> String {
        "\(account)/\(type)"
    }
}
