import Foundation

/// Maps keychain key types to environment variable names.
/// Keys follow the format "account/type" (e.g., "work/github-token").
/// The account portion is ignored — env vars are not account-scoped.
public struct EnvironmentKeychainStore: KeychainStoring {
    private static let typeToEnvVar: [String: String] = [
        "github-token": "GITHUB_TOKEN",
        "anthropic-api-key": "ANTHROPIC_API_KEY",
    ]

    private let environment: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    public func setString(_ string: String, forKey key: String) throws {
        throw KeychainStoreError.readOnly
    }

    public func string(forKey key: String) throws -> String {
        guard let envVar = Self.envVarName(forKey: key),
              let value = environment[envVar], !value.isEmpty else {
            throw KeychainStoreError.itemNotFound
        }
        return value
    }

    public func removeObject(forKey key: String) throws {
        throw KeychainStoreError.readOnly
    }

    public func allKeys() throws -> Set<String> {
        var keys = Set<String>()
        for (type, envVar) in Self.typeToEnvVar {
            if let value = environment[envVar], !value.isEmpty {
                keys.insert("env/\(type)")
            }
        }
        return keys
    }

    static func envVarName(forKey key: String) -> String? {
        guard let slashIndex = key.firstIndex(of: "/") else { return nil }
        let type = String(key[key.index(after: slashIndex)...])
        return typeToEnvVar[type]
    }
}
