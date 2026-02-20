import CLISDK
import ClaudeSDK
import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels

public struct SelectiveAnalyzeUseCase: Sendable {

    private let config: RepositoryConfiguration

    public init(config: RepositoryConfiguration) {
        self.config = config
    }

    public func execute(
        prNumber: Int,
        filter: AnalysisFilter,
        repoPath: String? = nil,
        commitHash: String? = nil
    ) -> AsyncThrowingStream<PhaseProgress<AnalysisOutput>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .analyze))

            Task {
                do {
                    let resolvedCommit = commitHash ?? SyncPRUseCase.resolveCommitHash(config: config, prNumber: prNumber)
                    let effectiveRepoPath = repoPath ?? config.repoPath

                    // Load all tasks from prepare phase
                    let allTasks: [AnalysisTaskOutput] = try PhaseOutputParser.parseAllPhaseFiles(
                        config: config, prNumber: prNumber, phase: .prepare, subdirectory: DataPathsService.prepareTasksSubdir, commitHash: resolvedCommit
                    )

                    // Apply filter
                    let filteredTasks = allTasks.filter { filter.matches($0) }

                    if filteredTasks.isEmpty {
                        continuation.yield(.log(text: "No tasks match the filter criteria\n"))

                        let output = try Self.buildMergedOutput(
                            config: config, prNumber: prNumber, allTasks: allTasks, cachedCount: 0, commitHash: resolvedCommit
                        )
                        continuation.yield(.completed(output: output))
                        continuation.finish()
                        return
                    }

                    let evalsDir = DataPathsService.phaseDirectory(
                        outputDir: config.resolvedOutputDir,
                        prNumber: prNumber,
                        phase: .analyze,
                        commitHash: resolvedCommit
                    )

                    // Partition filtered tasks into cached and fresh
                    let prOutputDir = "\(config.resolvedOutputDir)/\(prNumber)"
                    let (cachedResults, tasksToEvaluate) = AnalysisCacheService.partitionTasks(
                        tasks: filteredTasks, evalsDir: evalsDir, prOutputDir: prOutputDir
                    )

                    let cachedCount = cachedResults.count
                    let freshCount = tasksToEvaluate.count
                    let totalCount = filteredTasks.count

                    continuation.yield(.log(text: "Selective evaluation: \(totalCount) tasks match filter\n"))
                    continuation.yield(.log(text: AnalysisCacheService.startMessage(cachedCount: cachedCount, freshCount: freshCount, totalCount: totalCount) + "\n"))

                    // Seed cumulative evaluations with existing results from disk (prior runs)
                    var cumulativeEvaluations = try Self.loadExistingEvaluations(config: config, prNumber: prNumber, commitHash: resolvedCommit)

                    for (index, result) in cachedResults.enumerated() {
                        continuation.yield(.log(text: AnalysisCacheService.cachedTaskMessage(index: index + 1, totalCount: totalCount, result: result) + "\n"))
                        cumulativeEvaluations.append(result)
                        let cumOutput = AnalysisOutput.cumulative(evaluations: cumulativeEvaluations, tasks: allTasks, prNumber: prNumber, cachedCount: cachedCount)
                        continuation.yield(.analysisResult(result, cumulativeOutput: cumOutput))
                    }

                    if !tasksToEvaluate.isEmpty {
                        let resolver = CredentialResolver(settingsService: SettingsService(), githubAccount: config.githubAccount)
                        guard let anthropicKey = resolver.getAnthropicKey() else {
                            throw ClaudeAgentError.missingAPIKey
                        }
                        let agentEnv = ClaudeAgentEnvironment.build(anthropicAPIKey: anthropicKey)
                        let agentClient = ClaudeAgentClient(pythonEnvironment: PythonEnvironment(agentScriptPath: config.agentScriptPath), cliClient: CLIClient(), environment: agentEnv)
                        let analysisService = AnalysisService(agentClient: agentClient)

                        // runBatchAnalysis writes data-{taskId}.json per task immediately
                        let freshResults = try await analysisService.runBatchAnalysis(
                            tasks: tasksToEvaluate,
                            evalsDir: evalsDir,
                            repoPath: effectiveRepoPath,
                            onStart: { index, total, task in
                                let globalIndex = cachedCount + index
                                continuation.yield(.log(text: "[\(globalIndex)/\(totalCount)] Evaluating \(task.rule.name)...\n"))
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
                                cumulativeEvaluations.append(result)
                                let cumOutput = AnalysisOutput.cumulative(evaluations: cumulativeEvaluations, tasks: allTasks, prNumber: prNumber, cachedCount: cachedCount)
                                continuation.yield(.analysisResult(result, cumulativeOutput: cumOutput))
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

                        // Write task snapshots for the evaluated tasks (for cache)
                        try AnalysisCacheService.writeTaskSnapshots(tasks: tasksToEvaluate, evalsDir: evalsDir)

                        let violationCount = (cachedResults + freshResults).filter(\.isViolation).count
                        continuation.yield(.log(text: AnalysisCacheService.completionMessage(freshCount: freshCount, cachedCount: cachedCount, totalCount: totalCount, violationCount: violationCount) + "\n"))
                    }

                    // Re-read ALL evaluation results from disk to build merged output
                    let output = try Self.buildMergedOutput(
                        config: config, prNumber: prNumber, allTasks: allTasks, cachedCount: cachedCount, commitHash: resolvedCommit
                    )
                    continuation.yield(.completed(output: output))
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(error: error.localizedDescription, logs: ""))
                    continuation.finish()
                }
            }
        }
    }

    /// Load existing evaluation results from disk to seed cumulative tracking.
    private static func loadExistingEvaluations(config: RepositoryConfiguration, prNumber: Int, commitHash: String?) throws -> [RuleEvaluationResult] {
        let evalFiles = PhaseOutputParser.listPhaseFiles(
            config: config, prNumber: prNumber, phase: .analyze, commitHash: commitHash
        ).filter { $0.hasPrefix(DataPathsService.dataFilePrefix) }

        var evaluations: [RuleEvaluationResult] = []
        for file in evalFiles {
            let evaluation: RuleEvaluationResult = try PhaseOutputParser.parsePhaseOutput(
                config: config, prNumber: prNumber, phase: .analyze, filename: file, commitHash: commitHash
            )
            evaluations.append(evaluation)
        }
        return evaluations
    }

    /// Build an AnalysisOutput by reading all individual result files from disk.
    ///
    /// This merges selective results with any prior full-run results,
    /// giving the UI a complete picture of all evaluations.
    private static func buildMergedOutput(
        config: RepositoryConfiguration,
        prNumber: Int,
        allTasks: [AnalysisTaskOutput],
        cachedCount: Int,
        commitHash: String? = nil
    ) throws -> AnalysisOutput {
        let evalFiles = PhaseOutputParser.listPhaseFiles(
            config: config, prNumber: prNumber, phase: .analyze, commitHash: commitHash
        ).filter { $0.hasPrefix(DataPathsService.dataFilePrefix) }

        var evaluations: [RuleEvaluationResult] = []
        for file in evalFiles {
            let evaluation: RuleEvaluationResult = try PhaseOutputParser.parsePhaseOutput(
                config: config, prNumber: prNumber, phase: .analyze, filename: file, commitHash: commitHash
            )
            evaluations.append(evaluation)
        }

        let violationCount = evaluations.filter(\.isViolation).count
        let summary = AnalysisSummary(
            prNumber: prNumber,
            evaluatedAt: ISO8601DateFormatter().string(from: Date()),
            totalTasks: evaluations.count,
            violationsFound: violationCount,
            totalCostUsd: evaluations.compactMap(\.costUsd).reduce(0, +),
            totalDurationMs: evaluations.map(\.durationMs).reduce(0, +),
            results: evaluations
        )

        return AnalysisOutput(
            evaluations: evaluations,
            tasks: allTasks,
            summary: summary,
            cachedCount: cachedCount
        )
    }
}
