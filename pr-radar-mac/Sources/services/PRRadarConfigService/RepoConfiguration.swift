import Foundation

public struct RepoConfiguration: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var repoPath: String
    public var outputDir: String
    public var rulesDir: String
    public var isDefault: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        repoPath: String,
        outputDir: String = "",
        rulesDir: String = "",
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.repoPath = repoPath
        self.outputDir = outputDir
        self.rulesDir = rulesDir
        self.isDefault = isDefault
    }
}

public struct AppSettings: Codable, Sendable {
    public var configurations: [RepoConfiguration]

    public init(configurations: [RepoConfiguration] = []) {
        self.configurations = configurations
    }

    public var defaultConfiguration: RepoConfiguration? {
        configurations.first(where: { $0.isDefault }) ?? configurations.first
    }
}
