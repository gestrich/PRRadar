import CLISDK
import ClaudeSDK
import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels

public struct AnalysisOutput: Sendable {
    public let evaluations: [RuleEvaluationResult]
    public let tasks: [AnalysisTaskOutput]
    public let summary: AnalysisSummary
    public let cachedCount: Int

    public static let empty = AnalysisOutput(
        evaluations: [],
        summary: AnalysisSummary(prNumber: 0, evaluatedAt: "", totalTasks: 0, violationsFound: 0, totalCostUsd: 0, totalDurationMs: 0, results: [])
    )

    public init(evaluations: [RuleEvaluationResult], tasks: [AnalysisTaskOutput] = [], summary: AnalysisSummary, cachedCount: Int = 0) {
        self.evaluations = evaluations
        self.tasks = tasks
        self.summary = summary
        self.cachedCount = cachedCount
    }

    /// Merge evaluations with task metadata into structured comments.
    public var comments: [PRComment] {
        let taskMap = Dictionary(uniqueKeysWithValues: tasks.map { ($0.taskId, $0) })
        return evaluations.compactMap { $0.violationComment(task: taskMap[$0.taskId]) }
    }
}

public struct AnalyzeUseCase: Sendable {

    private let config: RepositoryConfiguration

    public init(config: RepositoryConfiguration) {
        self.config = config
    }

    public func execute(prNumber: String, repoPath: String? = nil, commitHash: String? = nil) -> AsyncThrowingStream<PhaseProgress<AnalysisOutput>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .analyze))

            Task {
                do {
                    let resolvedCommit = commitHash ?? SyncPRUseCase.resolveCommitHash(config: config, prNumber: prNumber)
                    let effectiveRepoPath = repoPath ?? config.repoPath

                    // Load tasks from prepare phase (sorted file-first, then rule name)
                    let tasks: [AnalysisTaskOutput] = try PhaseOutputParser.parseAllPhaseFiles(
                        config: config, prNumber: prNumber, phase: .prepare, subdirectory: DataPathsService.prepareTasksSubdir, commitHash: resolvedCommit
                    ).sorted()

                    let evalsDir = DataPathsService.phaseDirectory(
                        outputDir: config.resolvedOutputDir,
                        prNumber: prNumber,
                        phase: .analyze,
                        commitHash: resolvedCommit
                    )

                    // Handle case where no tasks were generated (legitimate scenario)
                    if tasks.isEmpty {
                        continuation.yield(.log(text: "No tasks to evaluate (phase completed successfully with 0 tasks)\n"))

                        try DataPathsService.ensureDirectoryExists(at: evalsDir)

                        let encoder = JSONEncoder()
                        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

                        // Write empty summary
                        let summary = AnalysisSummary(
                            prNumber: Int(prNumber) ?? 0,
                            evaluatedAt: ISO8601DateFormatter().string(from: Date()),
                            totalTasks: 0,
                            violationsFound: 0,
                            totalCostUsd: 0.0,
                            totalDurationMs: 0,
                            results: []
                        )
                        let summaryData = try encoder.encode(summary)
                        try summaryData.write(to: URL(fileURLWithPath: "\(evalsDir)/\(DataPathsService.summaryJSONFilename)"))

                        // Write phase_result.json
                        try PhaseResultWriter.writeSuccess(
                            phase: .analyze,
                            outputDir: config.resolvedOutputDir,
                            prNumber: prNumber,
                            commitHash: resolvedCommit,
                            stats: PhaseStats(artifactsProduced: 0)
                        )

                        let output = AnalysisOutput(evaluations: [], tasks: [], summary: summary)
                        continuation.yield(.completed(output: output))
                        continuation.finish()
                        return
                    }

                    // Partition tasks into cached (blob hash unchanged) and fresh (need evaluation)
                    let prOutputDir = "\(config.resolvedOutputDir)/\(prNumber)"
                    let (cachedResults, tasksToEvaluate) = AnalysisCacheService.partitionTasks(
                        tasks: tasks, evalsDir: evalsDir, prOutputDir: prOutputDir
                    )

                    let cachedCount = cachedResults.count
                    let freshCount = tasksToEvaluate.count
                    let totalCount = tasks.count

                    continuation.yield(.log(text: AnalysisCacheService.startMessage(cachedCount: cachedCount, freshCount: freshCount, totalCount: totalCount) + "\n"))

                    for (index, result) in cachedResults.enumerated() {
                        continuation.yield(.log(text: AnalysisCacheService.cachedTaskMessage(index: index + 1, totalCount: totalCount, result: result) + "\n"))
                        continuation.yield(.analysisResult(result, cumulativeOutput: .empty))
                    }

                    var freshResults: [RuleEvaluationResult] = []
                    var durationMs = 0
                    var totalCost = 0.0

                    if !tasksToEvaluate.isEmpty {
                        let resolver = CredentialResolver(settingsService: SettingsService(), githubAccount: config.githubAccount)
                        guard let anthropicKey = resolver.getAnthropicKey() else {
                            throw ClaudeAgentError.missingAPIKey
                        }
                        let agentEnv = ClaudeAgentEnvironment.build(anthropicAPIKey: anthropicKey)
                        let agentClient = ClaudeAgentClient(pythonEnvironment: PythonEnvironment(agentScriptPath: config.agentScriptPath), cliClient: CLIClient(), environment: agentEnv)
                        let analysisService = AnalysisService(agentClient: agentClient)

                        let startTime = Date()
                        freshResults = try await analysisService.runBatchAnalysis(
                            tasks: tasksToEvaluate,
                            evalsDir: evalsDir,
                            repoPath: effectiveRepoPath,
                            onStart: { index, total, task in
                                let globalIndex = cachedCount + index
                                let fileName = (task.focusArea.filePath as NSString).lastPathComponent
                                continuation.yield(.log(text: "[\(globalIndex)/\(totalCount)] \(fileName) — \(task.rule.name)...\n"))
                            },
                            onResult: { index, total, result in
                                let globalIndex = cachedCount + index
                                let status: String
                                switch result {
                                case .success(let s):
                                    status = s.evaluation.violatesRule ? "VIOLATION (\(s.evaluation.score)/10)" : "OK"
                                case .error(let e):
                                    status = "ERROR: \(e.errorMessage)"
                                }
                                continuation.yield(.log(text: "[\(globalIndex)/\(totalCount)] \(status)\n"))
                                continuation.yield(.analysisResult(result, cumulativeOutput: .empty))
                            },
                            onPrompt: { text, task in
                                continuation.yield(.aiPrompt(AIPromptContext(text: text, filePath: task.focusArea.filePath, ruleName: task.rule.name)))
                            },
                            onAIText: { text in
                                continuation.yield(.aiOutput(text: text))
                            },
                            onAIToolUse: { name in
                                continuation.yield(.aiToolUse(name: name))
                            }
                        )

                        durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
                        totalCost = freshResults.compactMap(\.costUsd).reduce(0, +)
                    }

                    // Write task snapshots for future cache checks
                    try AnalysisCacheService.writeTaskSnapshots(tasks: tasks, evalsDir: evalsDir)

                    // Combine cached and fresh results
                    let allResults = cachedResults + freshResults
                    let violationCount = allResults.filter(\.isViolation).count

                    let summary = AnalysisSummary(
                        prNumber: Int(prNumber) ?? 0,
                        evaluatedAt: ISO8601DateFormatter().string(from: Date()),
                        totalTasks: allResults.count,
                        violationsFound: violationCount,
                        totalCostUsd: totalCost,
                        totalDurationMs: durationMs,
                        results: allResults
                    )

                    // Write summary
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let summaryData = try encoder.encode(summary)
                    try summaryData.write(to: URL(fileURLWithPath: "\(evalsDir)/\(DataPathsService.summaryJSONFilename)"))

                    // Write phase_result.json
                    try PhaseResultWriter.writeSuccess(
                        phase: .analyze,
                        outputDir: config.resolvedOutputDir,
                        prNumber: prNumber,
                        commitHash: resolvedCommit,
                        stats: PhaseStats(
                            artifactsProduced: allResults.count,
                            durationMs: durationMs,
                            costUsd: totalCost
                        )
                    )

                    continuation.yield(.log(text: AnalysisCacheService.completionMessage(freshCount: freshCount, cachedCount: cachedCount, totalCount: totalCount, violationCount: violationCount) + "\n"))

                    let output = AnalysisOutput(evaluations: allResults, tasks: tasks, summary: summary, cachedCount: cachedCount)
                    continuation.yield(.completed(output: output))
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(error: error.localizedDescription, logs: ""))
                    continuation.finish()
                }
            }
        }
    }

    public static func parseOutput(config: RepositoryConfiguration, prNumber: String, commitHash: String? = nil) throws -> AnalysisOutput {
        let resolvedCommit = commitHash ?? SyncPRUseCase.resolveCommitHash(config: config, prNumber: prNumber)

        let summary: AnalysisSummary = try PhaseOutputParser.parsePhaseOutput(
            config: config, prNumber: prNumber, phase: .analyze, filename: DataPathsService.summaryJSONFilename, commitHash: resolvedCommit
        )

        let evalFiles = PhaseOutputParser.listPhaseFiles(
            config: config, prNumber: prNumber, phase: .analyze, commitHash: resolvedCommit
        ).filter { $0.hasPrefix(DataPathsService.dataFilePrefix) }

        var evaluations: [RuleEvaluationResult] = []
        for file in evalFiles {
            let evaluation: RuleEvaluationResult = try PhaseOutputParser.parsePhaseOutput(
                config: config, prNumber: prNumber, phase: .analyze, filename: file, commitHash: resolvedCommit
            )
            evaluations.append(evaluation)
        }

        let tasks: [AnalysisTaskOutput] = (try? PhaseOutputParser.parseAllPhaseFiles(
            config: config, prNumber: prNumber, phase: .prepare, subdirectory: DataPathsService.prepareTasksSubdir, commitHash: resolvedCommit
        )) ?? []

        return AnalysisOutput(evaluations: evaluations, tasks: tasks, summary: summary)
    }
}
