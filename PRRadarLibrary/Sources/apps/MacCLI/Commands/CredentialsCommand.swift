import ArgumentParser
import Foundation
import PRRadarConfigService
import PRReviewFeature

struct CredentialsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "credentials",
        abstract: "Manage credential accounts in the macOS Keychain",
        subcommands: [
            AddCredentialCommand.self,
            ListCredentialsCommand.self,
            RemoveCredentialCommand.self,
            ShowCredentialCommand.self,
        ],
        defaultSubcommand: ListCredentialsCommand.self
    )

    struct AddCredentialCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "add",
            abstract: "Add or update a credential account"
        )

        @Argument(help: "Credential account name")
        var account: String

        @Option(name: .long, help: "GitHub token")
        var githubToken: String?

        @Option(name: .long, help: "Anthropic API key")
        var anthropicKey: String?

        func run() async throws {
            guard githubToken != nil || anthropicKey != nil else {
                throw ValidationError("No tokens provided. Use --github-token and/or --anthropic-key.")
            }

            let useCase = SaveCredentialsUseCase(settingsService: SettingsService())
            try useCase.execute(
                account: account,
                githubToken: githubToken,
                anthropicKey: anthropicKey
            )

            var parts: [String] = []
            if githubToken != nil { parts.append("GitHub token") }
            if anthropicKey != nil { parts.append("Anthropic API key") }
            print("Saved \(parts.joined(separator: " and ")) for account '\(account)'.")
        }
    }

    struct ListCredentialsCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List credential accounts stored in the Keychain"
        )

        func run() async throws {
            let useCase = ListCredentialAccountsUseCase(settingsService: SettingsService())
            let accounts = try useCase.execute()

            if accounts.isEmpty {
                print("No credential accounts found.")
                print("Use 'config credentials add <account>' to create one.")
                return
            }

            print("Credential accounts:\n")
            for account in accounts {
                print("  \(account)")
            }
        }
    }

    struct RemoveCredentialCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "remove",
            abstract: "Remove a credential account from the Keychain"
        )

        @Argument(help: "Credential account name to remove")
        var account: String

        func run() async throws {
            let settingsService = SettingsService()
            let listUseCase = ListCredentialAccountsUseCase(settingsService: settingsService)
            let accounts = try listUseCase.execute()

            guard accounts.contains(account) else {
                throw ValidationError("Credential account '\(account)' not found.")
            }

            let removeUseCase = RemoveCredentialsUseCase(settingsService: settingsService)
            try removeUseCase.execute(account: account)
            print("Credential account '\(account)' removed.")
        }
    }

    struct ShowCredentialCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "show",
            abstract: "Show masked credential status for an account"
        )

        @Argument(help: "Credential account name")
        var account: String

        func run() async throws {
            let settingsService = SettingsService()
            let listUseCase = ListCredentialAccountsUseCase(settingsService: settingsService)
            let accounts = try listUseCase.execute()

            guard accounts.contains(account) else {
                throw ValidationError("Credential account '\(account)' not found.")
            }

            let githubMasked = maskedValue { try settingsService.loadGitHubToken(account: account) }
            let anthropicMasked = maskedValue { try settingsService.loadAnthropicKey(account: account) }

            print("Account: \(account)\n")
            print("  GitHub token:      \(githubMasked)")
            print("  Anthropic API key: \(anthropicMasked)")
        }

        private func maskedValue(_ load: () throws -> String) -> String {
            guard let value = try? load() else {
                return "not set"
            }
            guard value.count > 8 else { return "****" }
            return "\(value.prefix(4))...\(value.suffix(4))"
        }
    }
}
