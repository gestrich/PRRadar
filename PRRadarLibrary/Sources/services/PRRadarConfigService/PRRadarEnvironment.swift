import Foundation

public enum PRRadarEnvironment {
    public static let githubTokenKey = "GITHUB_TOKEN"
    public static let anthropicAPIKeyKey = "ANTHROPIC_API_KEY"
    /// Repos with no `credentialAccount` use this as the Keychain lookup key.
    /// Lets single-credential users skip account configuration entirely.
    static let defaultCredentialAccount = "default"

    public static func build(credentialAccount: String? = nil) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if env["HOME"] == nil {
            env["HOME"] = NSHomeDirectory()
        }
        let currentPath = env["PATH"] ?? ""
        let extraPaths = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")

        let dotEnv = loadDotEnv()
        for (key, value) in dotEnv where env[key] == nil {
            env[key] = value
        }
        loadKeychainSecrets(into: &env, credentialAccount: credentialAccount)

        return env
    }

    private static func loadKeychainSecrets(into env: inout [String: String], credentialAccount: String?) {
        let account = (credentialAccount?.isEmpty ?? true) ? defaultCredentialAccount : credentialAccount!
        let service = SettingsService()
        if env[anthropicAPIKeyKey] == nil {
            if let key = try? service.loadAnthropicKey(account: account) {
                env[anthropicAPIKeyKey] = key
            }
        }
        if env[githubTokenKey] == nil {
            if let token = try? service.loadGitHubToken(account: account) {
                env[githubTokenKey] = token
            }
        }
    }

    public static func loadDotEnv() -> [String: String] {
        var values: [String: String] = [:]
        var searchDir = FileManager.default.currentDirectoryPath
        while true {
            let envPath = (searchDir as NSString).appendingPathComponent(".env")
            if FileManager.default.fileExists(atPath: envPath),
               let contents = try? String(contentsOfFile: envPath, encoding: .utf8) {
                for line in contents.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
                    let parts = trimmed.split(separator: "=", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                    let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                    if values[key] == nil {
                        values[key] = value
                    }
                }
                return values
            }
            let parent = (searchDir as NSString).deletingLastPathComponent
            if parent == searchDir { return values }
            searchDir = parent
        }
    }
}
