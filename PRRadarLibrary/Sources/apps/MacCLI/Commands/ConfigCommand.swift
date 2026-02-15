import ArgumentParser
import Foundation
import PRRadarConfigService
import PRReviewFeature

struct ConfigCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Manage saved configurations",
        subcommands: [AddCommand.self, ListCommand.self, RemoveCommand.self, SetDefaultCommand.self, CredentialsCommand.self],
        defaultSubcommand: ListCommand.self
    )

    struct ListCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List saved configurations"
        )

        @Flag(name: .long, help: "Output results as JSON")
        var json: Bool = false

        func run() async throws {
            let useCase = LoadSettingsUseCase(settingsService: SettingsService())
            let settings = useCase.execute()

            if settings.configurations.isEmpty {
                if json {
                    print("[]")
                } else {
                    print("No configurations saved.")
                    print("Use the PRRadar Mac app or 'config add' to create configurations.")
                }
                return
            }

            if json {
                let data = try JSONEncoder.prettyEncoder.encode(settings.configurations)
                print(String(data: data, encoding: .utf8)!)
            } else {
                print("Saved configurations:\n")
                for config in settings.configurations {
                    print("  \(config.presentableDescription)\n")
                }
            }
        }
    }

    struct AddCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "add",
            abstract: "Add a new configuration"
        )

        @Argument(help: "Configuration name")
        var name: String

        @Option(name: .long, help: "Path to the repository")
        var repoPath: String

        @Option(name: .long, help: "Output directory for phase results")
        var outputDir: String = ""

        @Option(name: .long, help: "Rules directory")
        var rulesDir: String = ""

        @Option(name: .long, help: "GitHub account name for Keychain-stored token lookup")
        var githubAccount: String?

        @Flag(name: .long, help: "Set as default configuration")
        var setDefault: Bool = false

        func run() async throws {
            let saveUseCase = SaveConfigurationUseCase(settingsService: SettingsService())

            let config = RepositoryConfigurationJSON(
                name: name,
                repoPath: repoPath,
                outputDir: outputDir,
                rulesDir: rulesDir,
                isDefault: setDefault,
                githubAccount: githubAccount
            )

            let updated = try saveUseCase.execute(config: config)

            let saved = updated.configurations.first(where: { $0.name == name })!
            print("Added configuration:")
            print("  \(saved.presentableDescription)")
        }
    }

    struct RemoveCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "remove",
            abstract: "Remove a configuration"
        )

        @Argument(help: "Configuration name to remove")
        var name: String

        func run() async throws {
            let settingsService = SettingsService()
            let loadUseCase = LoadSettingsUseCase(settingsService: settingsService)
            let removeUseCase = RemoveConfigurationUseCase(settingsService: settingsService)

            let settings = loadUseCase.execute()

            guard let config = settings.configurations.first(where: { $0.name == name }) else {
                throw ValidationError("Configuration '\(name)' not found.")
            }

            _ = try removeUseCase.execute(id: config.id)
            print("Configuration '\(name)' removed.")
        }
    }

    struct SetDefaultCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set-default",
            abstract: "Set a configuration as the default"
        )

        @Argument(help: "Configuration name to set as default")
        var name: String

        func run() async throws {
            let settingsService = SettingsService()
            let loadUseCase = LoadSettingsUseCase(settingsService: settingsService)
            let setDefaultUseCase = SetDefaultConfigurationUseCase(settingsService: settingsService)

            let settings = loadUseCase.execute()

            guard let config = settings.configurations.first(where: { $0.name == name }) else {
                throw ValidationError("Configuration '\(name)' not found.")
            }

            _ = try setDefaultUseCase.execute(id: config.id)
            print("Configuration '\(name)' set as default.")
        }
    }
}
