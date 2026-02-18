import ArgumentParser
import Foundation
import PRRadarConfigService
import PRReviewFeature

struct SettingsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "settings",
        abstract: "Show or update general (non-repo) settings",
        subcommands: [ShowCommand.self, SetCommand.self],
        defaultSubcommand: ShowCommand.self
    )

    struct ShowCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "show",
            abstract: "Show all general settings"
        )

        func run() async throws {
            let service = SettingsService()
            let settings = LoadSettingsUseCase(settingsService: service).execute()
            print("General settings:\n")
            print("  output-dir: \(settings.outputDir)")
        }
    }

    struct SetCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set",
            abstract: "Update a general setting"
        )

        @Option(name: .long, help: "Global output directory for review data")
        var outputDir: String?

        func run() async throws {
            guard let outputDir else {
                throw ValidationError("No settings provided. Use --output-dir to set the output directory.")
            }

            let service = SettingsService()
            let useCase = UpdateOutputDirUseCase(settingsService: service)
            let settings = try useCase.execute(outputDir: outputDir)
            print("Settings updated:\n")
            print("  output-dir: \(settings.outputDir)")
        }
    }
}
