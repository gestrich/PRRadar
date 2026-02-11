import CLISDK
import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels

public struct EvaluationPhaseOutput: Sendable {
    public let evaluations: [RuleEvaluationResult]
    public let tasks: [EvaluationTaskOutput]
    public let summary: EvaluationSummary
    public let cachedCount: Int

    public init(evaluations: [RuleEvaluationResult], tasks: [EvaluationTaskOutput] = [], summary: EvaluationSummary, cachedCount: Int = 0) {
        self.evaluations = evaluations
        self.tasks = tasks
        self.summary = summary
        self.cachedCount = cachedCount
    }

    /// Merge evaluations with task metadata into structured comments.
    public var comments: [PRComment] {
        let taskMap = Dictionary(uniqueKeysWithValues: tasks.map { ($0.taskId, $0) })
        return evaluations
            .filter(\.evaluation.violatesRule)
            .map { PRComment.from(evaluation: $0, task: taskMap[$0.taskId]) }
    }
}

public struct EvaluateUseCase: Sendable {

    private let config: PRRadarConfig

    public init(config: PRRadarConfig) {
        self.config = config
    }

    public func execute(prNumber: String, repoPath: String? = nil) -> AsyncThrowingStream<PhaseProgress<EvaluationPhaseOutput>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .evaluations))

            Task {
                do {
                    let prOutputDir = "\(config.absoluteOutputDir)/\(prNumber)"
                    let effectiveRepoPath = repoPath ?? config.repoPath

                    // Load tasks from phase-4
                    let tasks: [EvaluationTaskOutput] = try PhaseOutputParser.parseAllPhaseFiles(
                        config: config, prNumber: prNumber, phase: .tasks
                    )

                    // Handle case where no tasks were generated (legitimate scenario)
                    if tasks.isEmpty {
                        continuation.yield(.log(text: "No tasks to evaluate (phase completed successfully with 0 tasks)\n"))

                        let evalsDir = "\(prOutputDir)/\(PRRadarPhase.evaluations.rawValue)"
                        try DataPathsService.ensureDirectoryExists(at: evalsDir)

                        let encoder = JSONEncoder()
                        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

                        // Write empty summary
                        let summary = EvaluationSummary(
                            prNumber: Int(prNumber) ?? 0,
                            evaluatedAt: ISO8601DateFormatter().string(from: Date()),
                            totalTasks: 0,
                            violationsFound: 0,
                            totalCostUsd: 0.0,
                            totalDurationMs: 0,
                            results: []
                        )
                        let summaryData = try encoder.encode(summary)
                        try summaryData.write(to: URL(fileURLWithPath: "\(evalsDir)/summary.json"))

                        // Write phase_result.json
                        try PhaseResultWriter.writeSuccess(
                            phase: .evaluations,
                            outputDir: config.absoluteOutputDir,
                            prNumber: prNumber,
                            stats: PhaseStats(artifactsProduced: 0)
                        )

                        let output = EvaluationPhaseOutput(evaluations: [], tasks: [], summary: summary)
                        continuation.yield(.completed(output: output))
                        continuation.finish()
                        return
                    }

                    let evalsDir = "\(prOutputDir)/\(PRRadarPhase.evaluations.rawValue)"

                    // Partition tasks into cached (blob hash unchanged) and fresh (need evaluation)
                    let (cachedResults, tasksToEvaluate) = EvaluationCacheService.partitionTasks(
                        tasks: tasks, evalsDir: evalsDir
                    )

                    let cachedCount = cachedResults.count
                    let freshCount = tasksToEvaluate.count
                    let totalCount = tasks.count

                    continuation.yield(.log(text: EvaluationCacheService.startMessage(cachedCount: cachedCount, freshCount: freshCount, totalCount: totalCount) + "\n"))

                    for (index, result) in cachedResults.enumerated() {
                        continuation.yield(.log(text: EvaluationCacheService.cachedTaskMessage(index: index + 1, totalCount: totalCount, result: result) + "\n"))
                    }

                    var freshResults: [RuleEvaluationResult] = []
                    var durationMs = 0
                    var totalCost = 0.0

                    if !tasksToEvaluate.isEmpty {
                        let bridgeClient = ClaudeBridgeClient(pythonEnvironment: PythonEnvironment(bridgeScriptPath: config.bridgeScriptPath), cliClient: CLIClient())
                        let evaluationService = EvaluationService(bridgeClient: bridgeClient)

                        let startTime = Date()
                        freshResults = try await evaluationService.runBatchEvaluation(
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

                        durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
                        totalCost = freshResults.compactMap(\.costUsd).reduce(0, +)
                    }

                    // Write task snapshots to phase-5 for future cache checks
                    try EvaluationCacheService.writeTaskSnapshots(tasks: tasks, evalsDir: evalsDir)

                    // Combine cached and fresh results
                    let allResults = cachedResults + freshResults
                    let violationCount = allResults.filter(\.evaluation.violatesRule).count

                    let summary = EvaluationSummary(
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
                    try summaryData.write(to: URL(fileURLWithPath: "\(evalsDir)/summary.json"))

                    // Write phase_result.json
                    try PhaseResultWriter.writeSuccess(
                        phase: .evaluations,
                        outputDir: config.absoluteOutputDir,
                        prNumber: prNumber,
                        stats: PhaseStats(
                            artifactsProduced: allResults.count,
                            durationMs: durationMs,
                            costUsd: totalCost
                        )
                    )

                    continuation.yield(.log(text: EvaluationCacheService.completionMessage(freshCount: freshCount, cachedCount: cachedCount, totalCount: totalCount, violationCount: violationCount) + "\n"))

                    let output = EvaluationPhaseOutput(evaluations: allResults, tasks: tasks, summary: summary, cachedCount: cachedCount)
                    continuation.yield(.completed(output: output))
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(error: error.localizedDescription, logs: ""))
                    continuation.finish()
                }
            }
        }
    }

    public static func parseOutput(config: PRRadarConfig, prNumber: String) throws -> EvaluationPhaseOutput {
        let summary: EvaluationSummary = try PhaseOutputParser.parsePhaseOutput(
            config: config, prNumber: prNumber, phase: .evaluations, filename: "summary.json"
        )

        let evalFiles = PhaseOutputParser.listPhaseFiles(
            config: config, prNumber: prNumber, phase: .evaluations
        ).filter { $0.hasPrefix(DataPathsService.dataFilePrefix) }

        var evaluations: [RuleEvaluationResult] = []
        for file in evalFiles {
            let evaluation: RuleEvaluationResult = try PhaseOutputParser.parsePhaseOutput(
                config: config, prNumber: prNumber, phase: .evaluations, filename: file
            )
            evaluations.append(evaluation)
        }

        let tasks: [EvaluationTaskOutput] = (try? PhaseOutputParser.parseAllPhaseFiles(
            config: config, prNumber: prNumber, phase: .tasks
        )) ?? []

        return EvaluationPhaseOutput(evaluations: evaluations, tasks: tasks, summary: summary)
    }
}
