import Foundation

public enum PathUtilities {
    /// Expands `~` in the path.
    public static func expandTilde(_ path: String) -> String {
        NSString(string: path).expandingTildeInPath
    }

    /// Expands `~`, then resolves relative paths against `basePath`.
    /// Absolute paths pass through with only tilde expansion.
    public static func resolve(_ path: String, relativeTo basePath: String) -> String {
        let expanded = expandTilde(path)
        if NSString(string: expanded).isAbsolutePath {
            return expanded
        }
        return "\(basePath)/\(expanded)"
    }
}
