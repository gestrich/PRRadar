import CLISDK
import PRRadarCLIService
import PRRadarConfigService
import PRRadarMacSDK
import PRRadarModels

public struct CommentPhaseOutput: Sendable {
    public let cliOutput: String
    public let posted: Bool
}

public struct PostCommentsUseCase: Sendable {

    private let config: PRRadarConfig
    private let environment: [String: String]

    public init(config: PRRadarConfig, environment: [String: String]) {
        self.config = config
        self.environment = environment
    }

    public func execute(
        prNumber: String,
        repo: String? = nil,
        minScore: String? = nil,
        dryRun: Bool = true
    ) -> AsyncThrowingStream<PhaseProgress<CommentPhaseOutput>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .evaluations))

            Task {
                do {
                    let runner = PRRadarCLIRunner()
                    let command = PRRadar.Agent.Comment(
                        prNumber: prNumber,
                        repo: repo,
                        minScore: minScore,
                        noInteractive: true,
                        dryRun: dryRun
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
                        let output = CommentPhaseOutput(
                            cliOutput: result.output,
                            posted: !dryRun
                        )
                        continuation.yield(.completed(output: output))
                    } else {
                        continuation.yield(.failed(
                            error: "Comment phase failed (exit code \(result.exitCode))",
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
}
