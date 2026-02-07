import CLISDK
import PRRadarCLIService
import PRRadarConfigService
import PRRadarMacSDK
import PRRadarModels

public struct ReportPhaseOutput: Sendable {
    public let report: ReviewReport
    public let markdownContent: String
}

public struct GenerateReportUseCase: Sendable {

    private let config: PRRadarConfig
    private let environment: [String: String]

    public init(config: PRRadarConfig, environment: [String: String]) {
        self.config = config
        self.environment = environment
    }

    public func execute(prNumber: String, minScore: String? = nil) -> AsyncThrowingStream<PhaseProgress<ReportPhaseOutput>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .report))

            Task {
                do {
                    let runner = PRRadarCLIRunner()
                    let command = PRRadar.Agent.Report(
                        prNumber: prNumber,
                        minScore: minScore
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
                            error: "Report phase failed (exit code \(result.exitCode))",
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

    private func parseOutput(prNumber: String) throws -> ReportPhaseOutput {
        let report: ReviewReport = try PhaseOutputParser.parsePhaseOutput(
            config: config, prNumber: prNumber, phase: .report, filename: "summary.json"
        )

        let markdown = try PhaseOutputParser.readPhaseTextFile(
            config: config, prNumber: prNumber, phase: .report, filename: "summary.md"
        )

        return ReportPhaseOutput(report: report, markdownContent: markdown)
    }
}
