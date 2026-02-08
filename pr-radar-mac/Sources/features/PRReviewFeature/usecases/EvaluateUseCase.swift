import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels

public struct EvaluationPhaseOutput: Sendable {
    public let evaluations: [RuleEvaluationResult]
    public let summary: EvaluationSummary

    public init(evaluations: [RuleEvaluationResult], summary: EvaluationSummary) {
        self.evaluations = evaluations
        self.summary = summary
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

                    guard !tasks.isEmpty else {
                        continuation.yield(.failed(error: "No tasks found. Run rules phase first.", logs: ""))
                        continuation.finish()
                        return
                    }

                    continuation.yield(.log(text: "Evaluating \(tasks.count) tasks...\n"))

                    let bridgeClient = ClaudeBridgeClient(bridgeScriptPath: config.bridgeScriptPath)
                    let evaluationService = EvaluationService(bridgeClient: bridgeClient)

                    let startTime = Date()
                    let results = try await evaluationService.runBatchEvaluation(
                        tasks: tasks,
                        outputDir: prOutputDir,
                        repoPath: effectiveRepoPath,
                        onStart: { index, total, task in
                            continuation.yield(.log(text: "[\(index)/\(total)] Evaluating \(task.rule.name)...\n"))
                        },
                        onResult: { index, total, result in
                            let status = result.evaluation.violatesRule ? "VIOLATION (\(result.evaluation.score)/10)" : "OK"
                            continuation.yield(.log(text: "[\(index)/\(total)] \(status)\n"))
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
                    let evalsDir = "\(prOutputDir)/\(PRRadarPhase.evaluations.rawValue)"
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let summaryData = try encoder.encode(summary)
                    try summaryData.write(to: URL(fileURLWithPath: "\(evalsDir)/summary.json"))

                    continuation.yield(.log(text: "Evaluation complete: \(violationCount) violations found\n"))

                    let output = EvaluationPhaseOutput(evaluations: results, summary: summary)
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
        ).filter { $0.hasSuffix(".json") && $0 != "summary.json" }

        var evaluations: [RuleEvaluationResult] = []
        for file in evalFiles {
            let evaluation: RuleEvaluationResult = try PhaseOutputParser.parsePhaseOutput(
                config: config, prNumber: prNumber, phase: .evaluations, filename: file
            )
            evaluations.append(evaluation)
        }

        return EvaluationPhaseOutput(evaluations: evaluations, summary: summary)
    }
}
