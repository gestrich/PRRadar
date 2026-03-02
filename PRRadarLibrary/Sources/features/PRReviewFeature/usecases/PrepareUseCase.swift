import CLISDK
import ClaudeSDK
import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels

public struct PrepareOutput: Sendable {
    public let focusAreas: [FocusArea]
    public let rules: [ReviewRule]
    public let tasks: [RuleRequest]

    public init(focusAreas: [FocusArea], rules: [ReviewRule], tasks: [RuleRequest]) {
        self.focusAreas = focusAreas
        self.rules = rules
        self.tasks = tasks
    }
}

public struct PrepareUseCase: Sendable {

    private let config: RepositoryConfiguration

    public init(config: RepositoryConfiguration) {
        self.config = config
    }

    public func execute(prNumber: Int, rulesDir: String, commitHash: String? = nil, historyProvider: GitHistoryProvider? = nil) -> AsyncThrowingStream<PhaseProgress<PrepareOutput>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .prepare))

            Task {
                do {
                    let resolvedCommit = commitHash ?? SyncPRUseCase.resolveCommitHash(config: config, prNumber: prNumber)

                    // Generate focus areas
                    continuation.yield(.log(text: "Generating focus areas...\n"))

                    let diffSnapshot = SyncPRUseCase.parseOutput(config: config, prNumber: prNumber, commitHash: resolvedCommit)
                    guard let fullDiff = diffSnapshot.fullDiff else {
                        continuation.yield(.failed(error: "No diff data found. Run sync phase first.", logs: ""))
                        continuation.finish()
                        return
                    }

                    let resolver = CredentialResolver(settingsService: SettingsService(), githubAccount: config.githubAccount)
                    guard let anthropicKey = resolver.getAnthropicKey() else {
                        throw ClaudeAgentError.missingAPIKey
                    }
                    let agentEnv = ClaudeAgentEnvironment.build(anthropicAPIKey: anthropicKey)
                    let agentClient = ClaudeAgentClient(pythonEnvironment: PythonEnvironment(agentScriptPath: config.agentScriptPath), cliClient: CLIClient(), environment: agentEnv)
                    let focusGenerator = FocusGeneratorService(agentClient: agentClient)

                    let focusDir = DataPathsService.phaseSubdirectory(
                        outputDir: config.resolvedOutputDir,
                        prNumber: prNumber,
                        phase: .prepare,
                        subdirectory: DataPathsService.prepareFocusAreasSubdir,
                        commitHash: resolvedCommit
                    )

                    let focusResults = try await focusGenerator.generateAllFocusAreas(
                        hunks: fullDiff.hunks,
                        prNumber: prNumber,
                        requestedTypes: [.file],
                        transcriptDir: focusDir,
                        onAIText: { text in
                            continuation.yield(.prepareOutput(text: text))
                        },
                        onAIToolUse: { name in
                            continuation.yield(.prepareToolUse(name: name))
                        }
                    )
                    try FileManager.default.createDirectory(atPath: focusDir, withIntermediateDirectories: true)
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

                    var allFocusAreas: [FocusArea] = []
                    var totalCost = 0.0
                    for (focusType, result) in focusResults {
                        allFocusAreas.append(contentsOf: result.focusAreas)
                        totalCost += result.generationCostUsd
                        let typeOutput = FocusAreaTypeOutput(
                            prNumber: prNumber,
                            generatedAt: ISO8601DateFormatter().string(from: Date()),
                            focusType: focusType.rawValue,
                            focusAreas: result.focusAreas,
                            totalHunksProcessed: result.totalHunksProcessed,
                            generationCostUsd: result.generationCostUsd
                        )
                        let data = try encoder.encode(typeOutput)
                        try data.write(to: URL(fileURLWithPath: "\(focusDir)/\(DataPathsService.dataFilePrefix)\(focusType.rawValue).json"))
                    }

                    continuation.yield(.log(text: "Focus areas: \(allFocusAreas.count) generated\n"))

                    // Load rules
                    guard !rulesDir.isEmpty else {
                        continuation.yield(.failed(error: "No rules directory specified", logs: ""))
                        continuation.finish()
                        return
                    }

                    continuation.yield(.log(text: "Loading rules from \(rulesDir)...\n"))

                    let gitOps = GitHubServiceFactory.createGitOps()
                    let ruleLoader = RuleLoaderService(gitOps: gitOps)
                    let allRules = try await ruleLoader.loadAllRules(rulesDir: rulesDir)

                    let rulesOutputDir = DataPathsService.phaseSubdirectory(
                        outputDir: config.resolvedOutputDir,
                        prNumber: prNumber,
                        phase: .prepare,
                        subdirectory: DataPathsService.prepareRulesSubdir,
                        commitHash: resolvedCommit
                    )
                    try FileManager.default.createDirectory(atPath: rulesOutputDir, withIntermediateDirectories: true)
                    let rulesData = try encoder.encode(allRules)
                    try rulesData.write(to: URL(fileURLWithPath: "\(rulesOutputDir)/\(DataPathsService.allRulesFilename)"))

                    continuation.yield(.log(text: "Rules loaded: \(allRules.count)\n"))

                    // Create tasks
                    let resolvedProvider: GitHistoryProvider = historyProvider ?? LocalGitHistoryProvider(gitOps: gitOps, repoPath: self.config.repoPath)

                    // Fetch the PR ref so git objects are available locally for blob hash lookups
                    if resolvedProvider is LocalGitHistoryProvider {
                        try await gitOps.fetchBranch(remote: "origin", branch: "pull/\(prNumber)/head", repoPath: self.config.repoPath)
                    }

                    let taskCreator = TaskCreatorService(ruleLoader: ruleLoader, gitOps: gitOps, historyProvider: resolvedProvider)
                    let prepareDir = DataPathsService.phaseDirectory(
                        outputDir: config.resolvedOutputDir,
                        prNumber: prNumber,
                        phase: .prepare,
                        commitHash: resolvedCommit
                    )
                    let tasks = try await taskCreator.createAndWriteTasks(
                        rules: allRules,
                        focusAreas: allFocusAreas,
                        outputDir: prepareDir,
                        commit: fullDiff.commitHash,
                        rulesDir: rulesDir
                    )

                    // Write phase_result.json for prepare phase
                    try PhaseResultWriter.writeSuccess(
                        phase: .prepare,
                        outputDir: config.resolvedOutputDir,
                        prNumber: prNumber,
                        commitHash: resolvedCommit,
                        stats: PhaseStats(
                            artifactsProduced: allFocusAreas.count + allRules.count + tasks.count,
                            costUsd: totalCost
                        )
                    )

                    continuation.yield(.log(text: "Tasks created: \(tasks.count)\n"))

                    let output = PrepareOutput(focusAreas: allFocusAreas, rules: allRules, tasks: tasks)
                    continuation.yield(.completed(output: output))
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(error: error.localizedDescription, logs: ""))
                    continuation.finish()
                }
            }
        }
    }

    public static func parseOutput(config: RepositoryConfiguration, prNumber: Int, commitHash: String? = nil) throws -> PrepareOutput {
        let resolvedCommit = commitHash ?? SyncPRUseCase.resolveCommitHash(config: config, prNumber: prNumber)

        let focusFiles = PhaseOutputParser.listPhaseFiles(
            config: config, prNumber: prNumber, phase: .prepare, subdirectory: DataPathsService.prepareFocusAreasSubdir, commitHash: resolvedCommit
        ).filter { $0.hasPrefix(DataPathsService.dataFilePrefix) }

        var allFocusAreas: [FocusArea] = []
        for file in focusFiles {
            let typeOutput: FocusAreaTypeOutput = try PhaseOutputParser.parsePhaseOutput(
                config: config, prNumber: prNumber, phase: .prepare, subdirectory: DataPathsService.prepareFocusAreasSubdir, filename: file, commitHash: resolvedCommit
            )
            allFocusAreas.append(contentsOf: typeOutput.focusAreas)
        }

        let rules: [ReviewRule] = try PhaseOutputParser.parsePhaseOutput(
            config: config, prNumber: prNumber, phase: .prepare, subdirectory: DataPathsService.prepareRulesSubdir, filename: DataPathsService.allRulesFilename, commitHash: resolvedCommit
        )

        let tasks: [RuleRequest] = try PhaseOutputParser.parseAllPhaseFiles(
            config: config, prNumber: prNumber, phase: .prepare, subdirectory: DataPathsService.prepareTasksSubdir, commitHash: resolvedCommit
        )

        return PrepareOutput(focusAreas: allFocusAreas, rules: rules, tasks: tasks)
    }
}
