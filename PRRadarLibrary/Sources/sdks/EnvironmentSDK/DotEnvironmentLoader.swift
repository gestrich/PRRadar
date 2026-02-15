import Foundation

public enum DotEnvironmentLoader {
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
