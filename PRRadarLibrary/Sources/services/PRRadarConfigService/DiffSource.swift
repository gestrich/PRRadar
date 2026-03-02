import Foundation

public enum DiffSource: String, Codable, Sendable, CaseIterable {
    case git
    case githubAPI = "github-api"

    public var displayName: String {
        switch self {
        case .git: return "Local Git"
        case .githubAPI: return "GitHub API"
        }
    }
}
