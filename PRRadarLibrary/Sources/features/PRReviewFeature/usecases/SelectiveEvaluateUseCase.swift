import CLISDK
import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels

public struct SelectiveEvaluateUseCase: Sendable {

    private let config: PRRadarConfig

    public init(config: PRRadarConfig) {
        self.config = config
    }

    public func execute(
        prNumber: String,
        filter: EvaluationFilter,
        repoPath: String? = nil
    ) -> AsyncThrowingStream<PhaseProgress<EvaluationPhaseOutput>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .analyze))

            Task {
                do {
                    let prOutputDir = "\(config.absoluteOutputDir)/\(prNumber)"
                    let effectiveRepoPath = repoPath ?? config.repoPath

                    // Load all tasks from phase-4
                    let allTasks: [EvaluationTaskOutput] = try PhaseOutputParser.parseAllPhaseFiles(
                        config: config, prNumber: prNumber, phase: .prepare, subdirectory: DataPathsService.prepareTasksSubdir
                    )

                    // Apply filter
                    let filteredTasks = allTasks.filter { filter.matches($0) }

                    if filteredTasks.isEmpty {
                        continuation.yield(.log(text: "No tasks match the filter criteria\n"))

                        let output = try Self.buildMergedOutput(
                            config: config, prNumber: prNumber, allTasks: allTasks, cachedCount: 0
                        )
                        continuation.yield(.completed(output: output))
                        continuation.finish()
                        return
                    }

                    let evalsDir = "\(prOutputDir)/\(PRRadarPhase.analyze.rawValue)"

                    // Partition filtered tasks into cached and fresh
                    let (cachedResults, tasksToEvaluate) = EvaluationCacheService.partitionTasks(
                        tasks: filteredTasks, evalsDir: evalsDir
                    )

                    let cachedCount = cachedResults.count
                    let freshCount = tasksToEvaluate.count
                    let totalCount = filteredTasks.count

                    continuation.yield(.log(text: "Selective evaluation: \(totalCount) tasks match filter\n"))
                    continuation.yield(.log(text: EvaluationCacheService.startMessage(cachedCount: cachedCount, freshCount: freshCount, totalCount: totalCount) + "\n"))

                    for (index, result) in cachedResults.enumerated() {
                        continuation.yield(.log(text: EvaluationCacheService.cachedTaskMessage(index: index + 1, totalCount: totalCount, result: result) + "\n"))
                        continuation.yield(.evaluationResult(result))
                    }

                    if !tasksToEvaluate.isEmpty {
                        let bridgeClient = ClaudeBridgeClient(pythonEnvironment: PythonEnvironment(bridgeScriptPath: config.bridgeScriptPath), cliClient: CLIClient())
                        let evaluationService = EvaluationService(bridgeClient: bridgeClient)

                        // runBatchEvaluation writes data-{taskId}.json per task immediately
                        let freshResults = try await evaluationService.runBatchEvaluation(
                            tasks: tasksToEvaluate,
                            outputDir: prOutputDir,
                            repoPath: effectiveRepoPath,
                            transcriptDir: evalsDir,
                            onStart: { index, total, task in
                                let globalIndex = cachedCount + index
                                continuation.yield(.log(text: "[\(globalIndex)/\(totalCount)] Evaluating \(task.rule.name)...\n"))
                            },
                            onResult: { index, total, result in
                                let globalIndex = cachedCount + index
                                let status = result.evaluation.violatesRule ? "VIOLATION (\(result.evaluation.score)/10)" : "OK"
                                continuation.yield(.log(text: "[\(globalIndex)/\(totalCount)] \(status)\n"))
                                continuation.yield(.evaluationResult(result))
                            },
                            onPrompt: { text in
                                continuation.yield(.aiPrompt(text: text))
                            },
                            onAIText: { text in
                                continuation.yield(.aiOutput(text: text))
                            },
                            onAIToolUse: { name in
                                continuation.yield(.aiToolUse(name: name))
                            }
                        )

                        // Write task snapshots for the evaluated tasks (for cache)
                        try EvaluationCacheService.writeTaskSnapshots(tasks: tasksToEvaluate, evalsDir: evalsDir)

                        let violationCount = (cachedResults + freshResults).filter(\.evaluation.violatesRule).count
                        continuation.yield(.log(text: EvaluationCacheService.completionMessage(freshCount: freshCount, cachedCount: cachedCount, totalCount: totalCount, violationCount: violationCount) + "\n"))
                    }

                    // Re-read ALL evaluation results from disk to build merged output
                    let output = try Self.buildMergedOutput(
                        config: config, prNumber: prNumber, allTasks: allTasks, cachedCount: cachedCount
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

    /// Build an EvaluationPhaseOutput by reading all individual result files from disk.
    ///
    /// This merges selective results with any prior full-run results,
    /// giving the UI a complete picture of all evaluations.
    private static func buildMergedOutput(
        config: PRRadarConfig,
        prNumber: String,
        allTasks: [EvaluationTaskOutput],
        cachedCount: Int
    ) throws -> EvaluationPhaseOutput {
        let evalFiles = PhaseOutputParser.listPhaseFiles(
            config: config, prNumber: prNumber, phase: .analyze
        ).filter { $0.hasPrefix(DataPathsService.dataFilePrefix) }

        var evaluations: [RuleEvaluationResult] = []
        for file in evalFiles {
            if let evaluation: RuleEvaluationResult = try? PhaseOutputParser.parsePhaseOutput(
                config: config, prNumber: prNumber, phase: .analyze, filename: file
            ) {
                evaluations.append(evaluation)
            }
        }

        let violationCount = evaluations.filter(\.evaluation.violatesRule).count
        let summary = EvaluationSummary(
            prNumber: Int(prNumber) ?? 0,
            evaluatedAt: ISO8601DateFormatter().string(from: Date()),
            totalTasks: evaluations.count,
            violationsFound: violationCount,
            totalCostUsd: evaluations.compactMap(\.costUsd).reduce(0, +),
            totalDurationMs: evaluations.map(\.durationMs).reduce(0, +),
            results: evaluations
        )

        return EvaluationPhaseOutput(
            evaluations: evaluations,
            tasks: allTasks,
            summary: summary,
            cachedCount: cachedCount
        )
    }
}
