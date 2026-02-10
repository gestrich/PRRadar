import CLISDK
import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels

public struct EvaluationPhaseOutput: Sendable {
    public let evaluations: [RuleEvaluationResult]
    public let tasks: [EvaluationTaskOutput]
    public let summary: EvaluationSummary

    public init(evaluations: [RuleEvaluationResult], tasks: [EvaluationTaskOutput] = [], summary: EvaluationSummary) {
        self.evaluations = evaluations
        self.tasks = tasks
        self.summary = summary
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

                    continuation.yield(.log(text: "Evaluating \(tasks.count) tasks...\n"))

                    let bridgeClient = ClaudeBridgeClient(pythonEnvironment: PythonEnvironment(bridgeScriptPath: config.bridgeScriptPath), cliClient: CLIClient())
                    let evaluationService = EvaluationService(bridgeClient: bridgeClient)

                    let evalsDir = "\(prOutputDir)/\(PRRadarPhase.evaluations.rawValue)"

                    let startTime = Date()
                    let results = try await evaluationService.runBatchEvaluation(
                        tasks: tasks,
                        outputDir: prOutputDir,
                        repoPath: effectiveRepoPath,
                        transcriptDir: evalsDir,
                        onStart: { index, total, task in
                            continuation.yield(.log(text: "[\(index)/\(total)] Evaluating \(task.rule.name)...\n"))
                        },
                        onResult: { index, total, result in
                            let status = result.evaluation.violatesRule ? "VIOLATION (\(result.evaluation.score)/10)" : "OK"
                            continuation.yield(.log(text: "[\(index)/\(total)] \(status)\n"))
                        },
                        onAIText: { text in
                            continuation.yield(.aiOutput(text: text))
                        },
                        onAIToolUse: { name in
                            continuation.yield(.aiToolUse(name: name))
                        }
                    )

                    let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
                    let totalCost = results.compactMap(\.costUsd).reduce(0, +)
                    let violationCount = results.filter(\.evaluation.violatesRule).count

                    let summary = EvaluationSummary(
                        prNumber: Int(prNumber) ?? 0,
                        evaluatedAt: ISO8601DateFormatter().string(from: Date()),
                        totalTasks: results.count,
                        violationsFound: violationCount,
                        totalCostUsd: totalCost,
                        totalDurationMs: durationMs,
                        results: results
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
                            artifactsProduced: results.count,
                            durationMs: durationMs,
                            costUsd: totalCost
                        )
                    )

                    continuation.yield(.log(text: "Evaluation complete: \(violationCount) violations found\n"))

                    let output = EvaluationPhaseOutput(evaluations: results, tasks: tasks, summary: summary)
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
