import Foundation

public struct RepositoryConfigurationJSON: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var repoPath: String
    public var rulesDir: String
    public var isDefault: Bool
    public var githubAccount: String

    public var presentableDescription: String {
        let header = isDefault ? "\(name) (default)" : name
        var lines = [header, "  repo:   \(repoPath)"]
        if !rulesDir.isEmpty {
            lines.append("  rules:  \(rulesDir)")
        }
        lines.append("  credential account: \(githubAccount)")
        return lines.joined(separator: "\n")
    }

    public init(
        id: UUID = UUID(),
        name: String,
        repoPath: String,
        rulesDir: String = "",
        isDefault: Bool = false,
        githubAccount: String
    ) {
        self.id = id
        self.name = name
        self.repoPath = repoPath
        self.rulesDir = rulesDir
        self.isDefault = isDefault
        self.githubAccount = githubAccount
    }
}

public struct AppSettings: Codable, Sendable {
    public var configurations: [RepositoryConfigurationJSON]
    public var outputDir: String

    public static let defaultOutputDir = "code-reviews"

    public init(configurations: [RepositoryConfigurationJSON] = [], outputDir: String = AppSettings.defaultOutputDir) {
        self.configurations = configurations
        self.outputDir = outputDir
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        configurations = try container.decode([RepositoryConfigurationJSON].self, forKey: .configurations)
        outputDir = try container.decodeIfPresent(String.self, forKey: .outputDir) ?? AppSettings.defaultOutputDir
    }

    public var defaultConfiguration: RepositoryConfigurationJSON? {
        configurations.first(where: { $0.isDefault }) ?? configurations.first
    }
}
