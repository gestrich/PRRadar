import Foundation

public enum PRRadarEnvironment {
    public static func build() -> [String: String] {
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

        return env
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
