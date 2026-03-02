import Foundation

public struct RepositoryConfigurationJSON: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var repoPath: String
    public var rulesDir: String
    public var isDefault: Bool
    public var githubAccount: String
    public var diffSource: DiffSource

    public var presentableDescription: String {
        let header = isDefault ? "\(name) (default)" : name
        var lines = [header, "  repo:   \(repoPath)"]
        if !rulesDir.isEmpty {
            lines.append("  rules:  \(rulesDir)")
        }
        lines.append("  credential account: \(githubAccount)")
        lines.append("  diff source: \(diffSource.rawValue)")
        return lines.joined(separator: "\n")
    }

    public init(
        id: UUID = UUID(),
        name: String,
        repoPath: String,
        rulesDir: String = "",
        isDefault: Bool = false,
        githubAccount: String,
        diffSource: DiffSource = .git
    ) {
        self.id = id
        self.name = name
        self.repoPath = repoPath
        self.rulesDir = rulesDir
        self.isDefault = isDefault
        self.githubAccount = githubAccount
        self.diffSource = diffSource
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        repoPath = try container.decode(String.self, forKey: .repoPath)
        rulesDir = try container.decode(String.self, forKey: .rulesDir)
        isDefault = try container.decode(Bool.self, forKey: .isDefault)
        githubAccount = try container.decode(String.self, forKey: .githubAccount)
        diffSource = try container.decodeIfPresent(DiffSource.self, forKey: .diffSource) ?? .git
    }
}