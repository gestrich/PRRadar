import CLISDK
import PRRadarCLIService
import PRRadarConfigService
import PRRadarMacSDK

public struct AnalyzeAllOutput: Sendable {
    public let cliOutput: String
}

public struct AnalyzeAllUseCase: Sendable {

    private let config: PRRadarConfig
    private let environment: [String: String]

    public init(config: PRRadarConfig, environment: [String: String]) {
        self.config = config
        self.environment = environment
    }

    public func execute(
        since: String,
        rulesDir: String? = nil,
        repoPath: String? = nil,
        githubDiff: Bool = false,
        minScore: String? = nil,
        repo: String? = nil,
        comment: Bool = false,
        limit: String? = nil,
        state: String? = nil
    ) -> AsyncThrowingStream<PhaseProgress<AnalyzeAllOutput>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .pullRequest))

            Task {
                do {
                    let runner = PRRadarCLIRunner()
                    let command = PRRadar.Agent.AnalyzeAll(
                        since: since,
                        rulesDir: rulesDir,
                        repoPath: repoPath,
                        githubDiff: githubDiff,
                        minScore: minScore,
                        repo: repo,
                        comment: comment,
                        limit: limit,
                        state: state
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
                        let output = AnalyzeAllOutput(cliOutput: result.output)
                        continuation.yield(.completed(output: output))
                    } else {
                        continuation.yield(.failed(
                            error: "Analyze-all failed (exit code \(result.exitCode))",
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
