import Foundation

public struct AppSettings: Codable, Sendable {
    public var configurations: [RepositoryConfigurationJSON]
    public var outputDir: String

    public static var defaultOutputDir: String {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        return desktop.appendingPathComponent("code-reviews").path
    }

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
