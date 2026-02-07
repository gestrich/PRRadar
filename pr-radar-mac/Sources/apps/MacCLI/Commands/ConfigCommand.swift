import ArgumentParser
import Foundation
import PRRadarConfigService

struct ConfigCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Manage saved configurations",
        subcommands: [ListCommand.self],
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
            let settings = SettingsService().load()

            if settings.configurations.isEmpty {
                if json {
                    print("[]")
                } else {
                    print("No configurations saved.")
                    print("Use the PRRadar Mac app to create configurations.")
                }
                return
            }

            if json {
                let data = try JSONEncoder.prettyEncoder.encode(settings.configurations)
                print(String(data: data, encoding: .utf8)!)
            } else {
                print("Saved configurations:\n")
                for config in settings.configurations {
                    let defaultMarker = config.isDefault ? " (default)" : ""
                    print("  \(config.name)\(defaultMarker)")
                    print("    repo:   \(config.repoPath)")
                    if !config.outputDir.isEmpty {
                        print("    output: \(config.outputDir)")
                    }
                    if !config.rulesDir.isEmpty {
                        print("    rules:  \(config.rulesDir)")
                    }
                    print("")
                }
            }
        }
    }
}
