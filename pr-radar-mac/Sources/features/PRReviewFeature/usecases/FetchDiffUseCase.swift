import CLISDK
import PRRadarCLIService
import PRRadarConfigService
import PRRadarMacSDK

public struct FetchDiffUseCase: Sendable {

    private let config: PRRadarConfig
    private let environment: [String: String]

    public init(
        config: PRRadarConfig,
        environment: [String: String]
    ) {
        self.config = config
        self.environment = environment
    }

    public func execute(prNumber: String) -> AsyncThrowingStream<PhaseProgress<[String]>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .pullRequest))

            Task {
                do {
                    let runner = PRRadarCLIRunner()
                    let command = PRRadar.Agent.Diff(
                        prNumber: prNumber,
                        repoPath: config.repoPath
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
                        let files = OutputFileReader.files(
                            in: config,
                            prNumber: prNumber,
                            phase: .pullRequest
                        )
                        continuation.yield(.completed(output: files))
                    } else {
                        continuation.yield(.failed(
                            error: "Phase 1 failed (exit code \(result.exitCode))",
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
