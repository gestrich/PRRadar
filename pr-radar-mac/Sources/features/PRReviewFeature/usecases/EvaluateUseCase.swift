import CLISDK
import PRRadarCLIService
import PRRadarConfigService
import PRRadarMacSDK
import PRRadarModels

public struct EvaluationPhaseOutput: Sendable {
    public let evaluations: [RuleEvaluationResult]
    public let summary: EvaluationSummary
}

public struct EvaluateUseCase: Sendable {

    private let config: PRRadarConfig
    private let environment: [String: String]

    public init(config: PRRadarConfig, environment: [String: String]) {
        self.config = config
        self.environment = environment
    }

    public func execute(prNumber: String, rules: String? = nil, repoPath: String? = nil) -> AsyncThrowingStream<PhaseProgress<EvaluationPhaseOutput>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .evaluations))

            Task {
                do {
                    let runner = PRRadarCLIRunner()
                    let command = PRRadar.Agent.Evaluate(
                        prNumber: prNumber,
                        rules: rules,
                        repoPath: repoPath
                    )

                    let outputStream = CLIOutputStream()
                    let logTask = Task {
                        for await event in await outputStream.makeStream() {
                            if let text = event.text, !event.isCommand {
                                continuation.yield(.log(text: text))
                            }
                        }
                    }

                    let result = try await runner.execute(
                        command: command,
                        config: config,
                        environment: environment,
                        output: outputStream
                    )

                    await outputStream.finishAll()
                    _ = await logTask.result

                    if result.isSuccess {
                        let output = try parseOutput(prNumber: prNumber)
                        continuation.yield(.completed(output: output))
                    } else {
                        continuation.yield(.failed(
                            error: "Evaluate phase failed (exit code \(result.exitCode))",
                            logs: result.errorOutput
                        ))
                    }
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(error: error.localizedDescription, logs: ""))
                    continuation.finish()
                }
            }
        }
    }

    private func parseOutput(prNumber: String) throws -> EvaluationPhaseOutput {
        let summary: EvaluationSummary = try PhaseOutputParser.parsePhaseOutput(
            config: config, prNumber: prNumber, phase: .evaluations, filename: "summary.json"
        )

        // Individual evaluation files (exclude summary.json)
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
