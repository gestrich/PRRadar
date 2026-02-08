import CLISDK
import PRRadarCLIService
import PRRadarConfigService
import PRRadarMacSDK
import PRRadarModels

public struct FetchPRListUseCase: Sendable {

    private let config: PRRadarConfig
    private let environment: [String: String]

    public init(
        config: PRRadarConfig,
        environment: [String: String]
    ) {
        self.config = config
        self.environment = environment
    }

    public func execute(
        limit: String? = nil,
        state: String? = nil,
        repoSlug: String? = nil
    ) -> AsyncThrowingStream<PhaseProgress<[PRMetadata]>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .pullRequest))

            Task {
                do {
                    let runner = PRRadarCLIRunner()
                    let command = PRRadar.Agent.ListPrs(
                        limit: limit,
                        state: state,
                        repo: repoSlug
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
                        let prs = PRDiscoveryService.discoverPRs(
                            outputDir: config.absoluteOutputDir,
                            repoSlug: repoSlug
                        )
                        continuation.yield(.completed(output: prs))
                    } else {
                        continuation.yield(.failed(
                            error: "list-prs failed (exit code \(result.exitCode))",
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
