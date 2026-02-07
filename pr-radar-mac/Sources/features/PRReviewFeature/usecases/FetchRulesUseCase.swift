import CLISDK
import PRRadarCLIService
import PRRadarConfigService
import PRRadarMacSDK
import PRRadarModels

public struct RulesPhaseOutput: Sendable {
    public let focusAreas: [FocusArea]
    public let rules: [ReviewRule]
    public let tasks: [EvaluationTaskOutput]
}

public struct FetchRulesUseCase: Sendable {

    private let config: PRRadarConfig
    private let environment: [String: String]

    public init(config: PRRadarConfig, environment: [String: String]) {
        self.config = config
        self.environment = environment
    }

    public func execute(prNumber: String, rulesDir: String?) -> AsyncThrowingStream<PhaseProgress<RulesPhaseOutput>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .rules))

            Task {
                do {
                    let runner = PRRadarCLIRunner()
                    let command = PRRadar.Agent.Rules(
                        prNumber: prNumber,
                        rulesDir: rulesDir
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
                            error: "Rules phase failed (exit code \(result.exitCode))",
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

    private func parseOutput(prNumber: String) throws -> RulesPhaseOutput {
        // Parse focus areas from phase-2 (per-type JSON files)
        let focusFiles = PhaseOutputParser.listPhaseFiles(
            config: config, prNumber: prNumber, phase: .focusAreas
        ).filter { $0.hasSuffix(".json") }

        var allFocusAreas: [FocusArea] = []
        for file in focusFiles {
            let typeOutput: FocusAreaTypeOutput = try PhaseOutputParser.parsePhaseOutput(
                config: config, prNumber: prNumber, phase: .focusAreas, filename: file
            )
            allFocusAreas.append(contentsOf: typeOutput.focusAreas)
        }

        // Parse rules from phase-3 (all-rules.json is a bare array)
        let rules: [ReviewRule] = try PhaseOutputParser.parsePhaseOutput(
            config: config, prNumber: prNumber, phase: .rules, filename: "all-rules.json"
        )

        // Parse tasks from phase-4 (one JSON per task)
        let tasks: [EvaluationTaskOutput] = try PhaseOutputParser.parseAllPhaseFiles(
            config: config, prNumber: prNumber, phase: .tasks
        )

        return RulesPhaseOutput(focusAreas: allFocusAreas, rules: rules, tasks: tasks)
    }
}
