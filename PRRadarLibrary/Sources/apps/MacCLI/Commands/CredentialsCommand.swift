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

        @Option(name: .long, help: "GitHub personal access token")
        var githubToken: String?

        @Option(name: .long, help: "Anthropic API key")
        var anthropicKey: String?

        @Option(name: .long, help: "GitHub App ID (use with --installation-id and --private-key-path)")
        var appId: String?

        @Option(name: .long, help: "GitHub App installation ID")
        var installationId: String?

        @Option(name: .long, help: "Path to GitHub App private key PEM file")
        var privateKeyPath: String?

        func run() async throws {
            let gitHubAuth = try resolveGitHubAuth()

            guard gitHubAuth != nil || anthropicKey != nil else {
                throw ValidationError("No credentials provided. Use --github-token or --app-id/--installation-id/--private-key-path, and optionally --anthropic-key.")
            }

            let useCase = SaveCredentialsUseCase(settingsService: SettingsService())
            try useCase.execute(account: account, gitHubAuth: gitHubAuth, anthropicKey: anthropicKey)

            var parts: [String] = []
            switch gitHubAuth {
            case .token: parts.append("GitHub token")
            case .app: parts.append("GitHub App credentials")
            case nil: break
            }
            if anthropicKey != nil { parts.append("Anthropic API key") }
            print("Saved \(parts.joined(separator: " and ")) for account '\(account)'.")
        }

        private func resolveGitHubAuth() throws -> GitHubAuth? {
            let hasToken = githubToken != nil
            let hasAppFields = appId != nil || installationId != nil || privateKeyPath != nil

            if hasToken && hasAppFields {
                throw ValidationError("Cannot use --github-token together with --app-id/--installation-id/--private-key-path. Choose one authentication method.")
            }

            if hasToken {
                return .token(githubToken!)
            }

            if hasAppFields {
                guard let appId else {
                    throw ValidationError("--app-id is required for GitHub App authentication.")
                }
                guard let installationId else {
                    throw ValidationError("--installation-id is required for GitHub App authentication.")
                }
                guard let privateKeyPath else {
                    throw ValidationError("--private-key-path is required for GitHub App authentication.")
                }
                let url = URL(fileURLWithPath: (privateKeyPath as NSString).expandingTildeInPath)
                let pem = try String(contentsOf: url, encoding: .utf8)
                return .app(appId: appId, installationId: installationId, privateKeyPEM: pem)
            }

            return nil
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

            print("Account: \(account)\n")

            switch settingsService.loadGitHubAuth(account: account) {
            case .token(let token):
                print("  GitHub auth:       Token (\(masked(token)))")
            case .app(let appId, _, _):
                print("  GitHub auth:       App (ID: \(masked(appId)))")
            case nil:
                print("  GitHub auth:       not set")
            }

            let anthropicMasked = maskedLoad { try settingsService.loadAnthropicKey(account: account) }
            print("  Anthropic API key: \(anthropicMasked)")
        }

        private func masked(_ value: String) -> String {
            guard value.count > 8 else { return "****" }
            return "\(value.prefix(4))...\(value.suffix(4))"
        }

        private func maskedLoad(_ load: () throws -> String) -> String {
            guard let value = try? load() else { return "not set" }
            return masked(value)
        }
    }
}
