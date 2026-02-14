import Foundation

public enum PRRadarEnvironment {
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

        loadDotEnv(into: &env)
        loadKeychainSecrets(into: &env, credentialAccount: credentialAccount)

        return env
    }

    // TODO: This needs research - It almost seems like 
    // the account is assocaited with both anthropic and github credentials, but the logic around it is not clear.
    // (the same account). This is not really the architecure we want.
    // There is not link between anthropic and Github. They are separate credentials that just happen to be loaded together here. The account is just a key to load the credentials.
    // TODO: These ANTHROPIC_API_KEY should be static let
    private static func loadKeychainSecrets(into env: inout [String: String], credentialAccount: String?) {
        let account = (credentialAccount?.isEmpty ?? true) ? "default" : credentialAccount!
        let service = SettingsService()
        if env["ANTHROPIC_API_KEY"] == nil {
            if let key = try? service.loadAnthropicKey(account: account) {
                env["ANTHROPIC_API_KEY"] = key
            }
        }
        if env["GITHUB_TOKEN"] == nil {
            if let token = try? service.loadGitHubToken(account: account) {
                env["GITHUB_TOKEN"] = token
            }
        }
    }

    private static func loadDotEnv(into env: inout [String: String]) {
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
                    if env[key] == nil {
                        env[key] = value
                    }
                }
                return
            }
            let parent = (searchDir as NSString).deletingLastPathComponent
            if parent == searchDir { return }
            searchDir = parent
        }
    }
}
