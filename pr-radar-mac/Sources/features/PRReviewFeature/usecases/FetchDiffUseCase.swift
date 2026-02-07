import PRRadarCLIService
import PRRadarConfigService
import PRRadarMacSDK

public struct FetchDiffUseCase: Sendable {

    private let runner: PRRadarCLIRunner
    private let config: PRRadarConfig
    private let environment: [String: String]

    public init(
        runner: PRRadarCLIRunner,
        config: PRRadarConfig,
        environment: [String: String]
    ) {
        self.runner = runner
        self.config = config
        self.environment = environment
    }

    public func execute(prNumber: String) -> AsyncThrowingStream<FetchDiffProgress, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running)

            Task {
                do {
                    let command = PRRadar.Agent.Diff(
                        prNumber: prNumber,
                        repoPath: config.repoPath
                    )

                    let result = try await runner.execute(
                        command: command,
                        config: config,
                        environment: environment
                    )

                    if result.isSuccess {
                        let files = OutputFileReader.files(
                            in: config,
                            prNumber: prNumber,
                            phase: .pullRequest
                        )
                        continuation.yield(.completed(files: files))
                    } else {
                        continuation.yield(.failed(
                            error: "Phase 1 failed (exit code \(result.exitCode))"
                        ))
                    }
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(error: error.localizedDescription))
                    continuation.finish()
                }
            }
        }
    }
}
