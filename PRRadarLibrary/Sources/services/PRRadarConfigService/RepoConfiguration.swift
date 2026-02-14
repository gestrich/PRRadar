import Foundation

public struct RepositoryConfigurationJSON: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var repoPath: String
    public var outputDir: String
    public var rulesDir: String
    public var isDefault: Bool
    public var credentialAccount: String?

    public var presentableDescription: String {
        let header = isDefault ? "\(name) (default)" : name
        var lines = [header, "  repo:   \(repoPath)"]
        if !outputDir.isEmpty {
            lines.append("  output: \(outputDir)")
        }
        if !rulesDir.isEmpty {
            lines.append("  rules:  \(rulesDir)")
        }
        if let credentialAccount {
            lines.append("  credentials: \(credentialAccount)")
        }
        return lines.joined(separator: "\n")
    }

    public init(
        id: UUID = UUID(),
        name: String,
        repoPath: String,
        outputDir: String = "",
        rulesDir: String = "",
        isDefault: Bool = false,
        credentialAccount: String? = nil
    ) {
        self.id = id
        self.name = name
        self.repoPath = repoPath
        self.outputDir = outputDir
        self.rulesDir = rulesDir
        self.isDefault = isDefault
        self.credentialAccount = credentialAccount
    }
}

public struct AppSettings: Codable, Sendable {
    public var configurations: [RepositoryConfigurationJSON]

    public init(configurations: [RepositoryConfigurationJSON] = []) {
        self.configurations = configurations
    }

    public var defaultConfiguration: RepositoryConfigurationJSON? {
        configurations.first(where: { $0.isDefault }) ?? configurations.first
    }
}
