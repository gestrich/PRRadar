import ArgumentParser
import Foundation
import PRRadarConfigService
import PRRadarModels
import PRReviewFeature

struct RefreshCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "refresh",
        abstract: "Fetch recent PRs from GitHub"
    )

    @Option(name: .long, help: "Named configuration from settings")
    var config: String?

    @Option(name: .long, help: "Path to the repository")
    var repoPath: String?

    @Option(name: .long, help: "Output directory for phase results")
    var outputDir: String?

    @Option(name: .long, help: "Maximum number of PRs to fetch")
    var limit: String?

    @Option(name: .long, help: "PR state filter (open, closed, merged, all)")
    var state: String?

    @Flag(name: .long, help: "Output results as JSON")
    var json: Bool = false

    func run() async throws {
        var resolvedRepoPath = repoPath
        var resolvedOutputDir = outputDir

        if let configName = config {
            let settings = SettingsService().load()
            guard let namedConfig = settings.configurations.first(where: { $0.name == configName }) else {
                throw CLIError.configNotFound(configName)
            }
            resolvedRepoPath = resolvedRepoPath ?? namedConfig.repoPath
            resolvedOutputDir = resolvedOutputDir ?? (namedConfig.outputDir.isEmpty ? nil : namedConfig.outputDir)
        }

        let venvBinPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".venv/bin")
            .path

        let prRadarConfig = PRRadarConfig(
            venvBinPath: venvBinPath,
            repoPath: resolvedRepoPath ?? FileManager.default.currentDirectoryPath,
            outputDir: resolvedOutputDir ?? "code-reviews"
        )
        let environment = resolveEnvironment(config: prRadarConfig)

        let useCase = FetchPRListUseCase(config: prRadarConfig, environment: environment)
        let repoSlug = PRDiscoveryService.repoSlug(fromRepoPath: prRadarConfig.repoPath)

        if !json {
            print("Fetching recent PRs from GitHub...")
        }

        for try await progress in useCase.execute(limit: limit, state: state, repoSlug: repoSlug) {
            switch progress {
            case .running:
                break
            case .log(let text):
                if !json { print(text, terminator: "") }
            case .completed(let prs):
                if json {
                    let encoded = prs.map { pr in
                        [
                            "number": pr.number,
                            "title": pr.title,
                            "author": pr.author.login,
                            "state": pr.state,
                            "branch": pr.headRefName,
                        ] as [String: Any]
                    }
                    let data = try JSONSerialization.data(withJSONObject: encoded, options: [.prettyPrinted, .sortedKeys])
                    print(String(data: data, encoding: .utf8)!)
                } else {
                    print("\nFetched \(prs.count) PRs:")
                    for pr in prs {
                        print("  #\(pr.number) \(pr.title) (\(pr.author.login))")
                    }
                }
            case .failed(let error, let logs):
                if !logs.isEmpty { printError(logs) }
                throw CLIError.phaseFailed("Refresh failed: \(error)")
            }
        }
    }
}
