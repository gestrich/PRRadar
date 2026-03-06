import Foundation

public struct RepositoryConfigurationJSON: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var repoPath: String
    public var rulePaths: [RulePath]
    public var isDefault: Bool
    public var githubAccount: String
    public var diffSource: DiffSource

    public var presentableDescription: String {
        let header = isDefault ? "\(name) (default)" : name
        var lines = [header, "  repo:   \(repoPath)"]
        if !rulePaths.isEmpty {
            lines.append("  rule paths:")
            for rulePath in rulePaths {
                let defaultMarker = rulePath.isDefault ? " (default)" : ""
                lines.append("    \(rulePath.name): \(rulePath.path)\(defaultMarker)")
            }
        }
        lines.append("  credential account: \(githubAccount)")
        lines.append("  diff source: \(diffSource.rawValue)")
        return lines.joined(separator: "\n")
    }

    public init(
        id: UUID = UUID(),
        name: String,
        repoPath: String,
        rulePaths: [RulePath] = [],
        isDefault: Bool = false,
        githubAccount: String,
        diffSource: DiffSource = .git
    ) {
        self.id = id
        self.name = name
        self.repoPath = repoPath
        self.rulePaths = rulePaths
        self.isDefault = isDefault
        self.githubAccount = githubAccount
        self.diffSource = diffSource
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        repoPath = try container.decode(String.self, forKey: .repoPath)
        rulePaths = try container.decodeIfPresent([RulePath].self, forKey: .rulePaths) ?? []
        isDefault = try container.decode(Bool.self, forKey: .isDefault)
        githubAccount = try container.decode(String.self, forKey: .githubAccount)
        diffSource = try container.decodeIfPresent(DiffSource.self, forKey: .diffSource) ?? .git
    }
}
