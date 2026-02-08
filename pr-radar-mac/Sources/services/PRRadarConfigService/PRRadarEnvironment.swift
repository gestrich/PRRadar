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
        return env
    }
}
