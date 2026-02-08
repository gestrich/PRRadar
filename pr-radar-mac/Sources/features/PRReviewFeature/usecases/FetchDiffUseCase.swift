import CLISDK
import PRRadarCLIService
import PRRadarConfigService
import PRRadarMacSDK
import PRRadarModels

public struct DiffPhaseSnapshot: Sendable {
    public let files: [String]
    public let fullDiff: GitDiff?
    public let effectiveDiff: GitDiff?
    public let moveReport: MoveReport?

    public init(files: [String], fullDiff: GitDiff?, effectiveDiff: GitDiff?, moveReport: MoveReport?) {
        self.files = files
        self.fullDiff = fullDiff
        self.effectiveDiff = effectiveDiff
        self.moveReport = moveReport
    }
}

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

    public static func parseOutput(config: PRRadarConfig, prNumber: String) -> DiffPhaseSnapshot {
        let files = OutputFileReader.files(
            in: config,
            prNumber: prNumber,
            phase: .pullRequest
        )

        let fullDiff: GitDiff? = {
            guard let diffText = try? PhaseOutputParser.readPhaseTextFile(
                config: config, prNumber: prNumber, phase: .pullRequest, filename: "diff-parsed.md"
            ),
            let parsed: PRDiffOutput = try? PhaseOutputParser.parsePhaseOutput(
                config: config, prNumber: prNumber, phase: .pullRequest, filename: "diff-parsed.json"
            ) else { return nil }
            return GitDiff.fromDiffContent(diffText, commitHash: parsed.commitHash)
        }()

        let effectiveDiff: GitDiff? = {
            guard let effectiveText = try? PhaseOutputParser.readPhaseTextFile(
                config: config, prNumber: prNumber, phase: .pullRequest, filename: "effective-diff-parsed.md"
            ),
            let parsed: PRDiffOutput = try? PhaseOutputParser.parsePhaseOutput(
                config: config, prNumber: prNumber, phase: .pullRequest, filename: "effective-diff-parsed.json"
            ) else { return nil }
            return GitDiff.fromDiffContent(effectiveText, commitHash: parsed.commitHash)
        }()

        let moveReport: MoveReport? = try? PhaseOutputParser.parsePhaseOutput(
            config: config, prNumber: prNumber, phase: .pullRequest, filename: "effective-diff-moves.json"
        )

        return DiffPhaseSnapshot(files: files, fullDiff: fullDiff, effectiveDiff: effectiveDiff, moveReport: moveReport)
    }

    public func execute(prNumber: String) -> AsyncThrowingStream<PhaseProgress<DiffPhaseSnapshot>, Error> {
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
                        let snapshot = Self.parseOutput(config: config, prNumber: prNumber)
                        continuation.yield(.completed(output: snapshot))
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
