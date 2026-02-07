import PRRadarCLIService
import PRRadarConfigService
import PRRadarMacSDK
import PRRadarModels

public struct AnalyzePhaseOutput: Sendable {
    public let cliOutput: String
    public let files: [PRRadarPhase: [String]]
}

public struct AnalyzeUseCase: Sendable {

    private let config: PRRadarConfig
    private let environment: [String: String]

    public init(config: PRRadarConfig, environment: [String: String]) {
        self.config = config
        self.environment = environment
    }

    public func execute(
        prNumber: String,
        rulesDir: String? = nil,
        repoPath: String? = nil,
        githubDiff: Bool = false,
        stopAfter: String? = nil,
        skipTo: String? = nil,
        noDryRun: Bool = false,
        minScore: String? = nil,
        repo: String? = nil
    ) -> AsyncThrowingStream<PhaseProgress<AnalyzePhaseOutput>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .pullRequest))

            Task {
                do {
                    let runner = PRRadarCLIRunner()
                    let command = PRRadar.Agent.Analyze(
                        prNumber: prNumber,
                        rulesDir: rulesDir,
                        repoPath: repoPath,
                        githubDiff: githubDiff,
                        stopAfter: stopAfter,
                        skipTo: skipTo,
                        noInteractive: true,
                        noDryRun: noDryRun,
                        minScore: minScore,
                        repo: repo
                    )

                    let result = try await runner.execute(
                        command: command,
                        config: config,
                        environment: environment
                    )

                    if result.isSuccess {
                        var filesByPhase: [PRRadarPhase: [String]] = [:]
                        for phase in PRRadarPhase.allCases {
                            let files = OutputFileReader.files(in: config, prNumber: prNumber, phase: phase)
                            if !files.isEmpty {
                                filesByPhase[phase] = files
                            }
                        }

                        let output = AnalyzePhaseOutput(
                            cliOutput: result.output,
                            files: filesByPhase
                        )
                        continuation.yield(.completed(output: output))
                    } else {
                        continuation.yield(.failed(
                            error: "Analyze pipeline failed (exit code \(result.exitCode))",
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
