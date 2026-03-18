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
        execute(prNumber: prNumber, rulesDirs: [rulesDir], commitHash: commitHash, historyProvider: historyProvider)
    }

    public func execute(prNumber: Int, rulesDirs: [String], commitHash: String? = nil, historyProvider: GitHistoryProvider? = nil) -> AsyncThrowingStream<PhaseProgress<PrepareOutput>, Error> {
        AsyncThrowingStream<PhaseProgress<PrepareOutput>, Error>(PhaseProgress<PrepareOutput>.self) { continuation in
            continuation.yield(.running(phase: .prepare))

            Task {
                do {
                    let resolvedCommit = commitHash ?? SyncPRUseCase.resolveCommitHash(config: config, prNumber: prNumber)

                    let diffSnapshot = SyncPRUseCase.parseOutput(config: config, prNumber: prNumber, commitHash: resolvedCommit)
                    guard let rawDiff = diffSnapshot.prDiff else {
                        continuation.yield(.failed(error: "No diff data found. Run sync phase first.", logs: ""))
                        continuation.finish()
                        return
                    }

                    let prDiff = rawDiff.excludingPaths(self.config.excludePaths)

                    let focusDir = DataPathsService.phaseSubdirectory(
                        outputDir: config.resolvedOutputDir,
                        prNumber: prNumber,
                        phase: .prepare,
                        subdirectory: DataPathsService.prepareFocusAreasSubdir,
                        commitHash: resolvedCommit
                    )

                    let existingFocusFiles = (try? FileManager.default.contentsOfDirectory(atPath: focusDir))?.filter {
                        $0.hasPrefix(DataPathsService.dataFilePrefix) && $0.hasSuffix(".json")
                    } ?? []

                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

                    var allFocusAreas: [FocusArea] = []
                    var totalCost = 0.0

                    if !existingFocusFiles.isEmpty {
                        continuation.yield(.log(text: "Loading cached focus areas from disk...\n"))
                        for file in existingFocusFiles {
                            let filePath = "\(focusDir)/\(file)"
                            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
                            let typeOutput = try JSONDecoder().decode(FocusAreaTypeOutput.self, from: data)
                            allFocusAreas.append(contentsOf: typeOutput.focusAreas)
                        }
                        continuation.yield(.log(text: "Focus areas: \(allFocusAreas.count) loaded from cache\n"))
                    } else {
                        continuation.yield(.log(text: "Generating focus areas...\n"))

                        let resolver = CredentialResolver(settingsService: SettingsService(), githubAccount: config.githubAccount)
                        guard let anthropicKey = resolver.getAnthropicKey() else {
                            throw ClaudeAgentError.missingAPIKey
                        }
                        let agentEnv = ClaudeAgentEnvironment.build(anthropicAPIKey: anthropicKey)
                        let agentClient = ClaudeAgentClient(pythonEnvironment: PythonEnvironment(agentScriptPath: config.agentScriptPath), cliClient: CLIClient(), environment: agentEnv)
                        let focusGenerator = FocusGeneratorService(agentClient: agentClient)

                        let focusResults = try await focusGenerator.generateAllFocusAreas(
                            hunks: prDiff.toGitDiff().hunks,
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
                    }

                    // Load rules from all directories
                    let validRulesDirs = rulesDirs.filter { !$0.isEmpty }
                    guard !validRulesDirs.isEmpty else {
                        continuation.yield(.failed(error: "No rules directory specified", logs: ""))
                        continuation.finish()
                        return
                    }

                    let gitOps = try await GitHubServiceFactory.createGitOps(githubAccount: self.config.githubAccount)
                    let ruleLoader = RuleLoaderService(gitOps: gitOps)
                    var allRules: [ReviewRule] = []
                    var rulesByDir: [(rulesDir: String, rules: [ReviewRule])] = []

                    for rulesDir in validRulesDirs {
                        continuation.yield(.log(text: "Loading rules from \(rulesDir)...\n"))
                        let rules = try await ruleLoader.loadAllRules(rulesDir: rulesDir)
                        allRules.append(contentsOf: rules)
                        rulesByDir.append((rulesDir, rules))

                        let rulesData = try encoder.encode(rules)
                        let rulesFilePath = try DataPathsService.rulesFilePath(
                            outputDir: config.resolvedOutputDir, prNumber: prNumber,
                            rulesDir: rulesDir, commitHash: resolvedCommit
                        )
                        try rulesData.write(to: URL(fileURLWithPath: rulesFilePath))
                    }

                    continuation.yield(.log(text: "Rules loaded: \(allRules.count)\n"))

                    // Create tasks
                    let resolvedProvider: GitHistoryProvider
                    if let historyProvider {
                        resolvedProvider = historyProvider
                    } else {
                        let (gitHub, _) = try await GitHubServiceFactory.create(repoPath: config.repoPath, githubAccount: config.githubAccount)
                        resolvedProvider = GitHubServiceFactory.createHistoryProvider(
                            diffSource: config.diffSource,
                            gitHub: gitHub,
                            gitOps: gitOps,
                            repoPath: config.repoPath,
                            prNumber: prNumber,
                            baseBranch: "",
                            headBranch: ""
                        )
                    }

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

                    var allTasks: [RuleRequest] = []
                    for (rulesDir, rules) in rulesByDir {
                        let tasks = try await taskCreator.createAndWriteTasks(
                            rules: rules,
                            focusAreas: allFocusAreas,
                            prDiff: prDiff,
                            outputDir: prepareDir,
                            rulesDir: rulesDir
                        )
                        allTasks.append(contentsOf: tasks)
                    }

                    // Write phase_result.json with cumulative artifact count across all rule dirs
                    let tasksDir = DataPathsService.phaseSubdirectory(
                        outputDir: config.resolvedOutputDir, prNumber: prNumber,
                        phase: .prepare, subdirectory: DataPathsService.prepareTasksSubdir,
                        commitHash: resolvedCommit
                    )
                    let totalTasksOnDisk = Self.countDataFiles(inDirectory: tasksDir)
                    let rulesSubdir = DataPathsService.phaseSubdirectory(
                        outputDir: config.resolvedOutputDir, prNumber: prNumber,
                        phase: .prepare, subdirectory: DataPathsService.prepareRulesSubdir,
                        commitHash: resolvedCommit
                    )
                    let totalRulesFiles = Self.countRulesFiles(inDirectory: rulesSubdir)

                    try PhaseResultWriter.writeSuccess(
                        phase: .prepare,
                        outputDir: config.resolvedOutputDir,
                        prNumber: prNumber,
                        commitHash: resolvedCommit,
                        stats: PhaseStats(
                            artifactsProduced: allFocusAreas.count + totalRulesFiles + totalTasksOnDisk,
                            costUsd: totalCost
                        )
                    )

                    continuation.yield(.log(text: "Tasks created: \(allTasks.count)\n"))

                    let output = PrepareOutput(focusAreas: allFocusAreas, rules: allRules, tasks: allTasks)
                    continuation.yield(.completed(output: output))
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(error: error.localizedDescription, logs: ""))
                    continuation.finish()
                }
            }
        }
    }

    // MARK: - Helpers

    private static func countDataFiles(inDirectory dir: String) -> Int {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
            .filter { $0.hasPrefix(DataPathsService.dataFilePrefix) }
            .count
    }

    private static func countRulesFiles(inDirectory dir: String) -> Int {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
            .filter { DataPathsService.isRulesFile($0) }
            .count
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

        let rulesFiles = PhaseOutputParser.listRulesFiles(
            config: config, prNumber: prNumber, commitHash: resolvedCommit
        )

        guard !focusFiles.isEmpty || !rulesFiles.isEmpty else {
            throw NSError(domain: "PrepareUseCase", code: 1, userInfo: [NSLocalizedDescriptionKey: "No prepare output found"])
        }

        var rules: [ReviewRule] = []
        for file in rulesFiles {
            let fileRules: [ReviewRule] = try PhaseOutputParser.parsePhaseOutput(
                config: config, prNumber: prNumber, phase: .prepare, subdirectory: DataPathsService.prepareRulesSubdir, filename: file, commitHash: resolvedCommit
            )
            rules.append(contentsOf: fileRules)
        }

        let tasks: [RuleRequest] = try PhaseOutputParser.parseAllPhaseFiles(
            config: config, prNumber: prNumber, phase: .prepare, subdirectory: DataPathsService.prepareTasksSubdir, commitHash: resolvedCommit
        )

        return PrepareOutput(focusAreas: allFocusAreas, rules: rules, tasks: tasks)
    }
}
