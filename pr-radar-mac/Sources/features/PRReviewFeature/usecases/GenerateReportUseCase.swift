import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels

public struct ReportPhaseOutput: Sendable {
    public let report: ReviewReport
    public let markdownContent: String

    public init(report: ReviewReport, markdownContent: String) {
        self.report = report
        self.markdownContent = markdownContent
    }
}

public struct GenerateReportUseCase: Sendable {

    private let config: PRRadarConfig

    public init(config: PRRadarConfig) {
        self.config = config
    }

    public func execute(prNumber: String, minScore: String? = nil) -> AsyncThrowingStream<PhaseProgress<ReportPhaseOutput>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .report))

            Task {
                do {
                    guard let prNum = Int(prNumber) else {
                        continuation.yield(.failed(error: "Invalid PR number: \(prNumber)", logs: ""))
                        continuation.finish()
                        return
                    }

                    let prOutputDir = "\(config.absoluteOutputDir)/\(prNumber)"
                    let scoreThreshold = Int(minScore ?? "5") ?? 5

                    continuation.yield(.log(text: "Generating report (min score: \(scoreThreshold))...\n"))

                    let reportService = ReportGeneratorService()
                    let report = try reportService.generateReport(
                        prNumber: prNum,
                        minScore: scoreThreshold,
                        outputDir: prOutputDir
                    )

                    let (_, _) = try reportService.saveReport(report: report, outputDir: prOutputDir)

                    // Write phase_result.json
                    try PhaseResultWriter.writeSuccess(
                        phase: .report,
                        outputDir: config.absoluteOutputDir,
                        prNumber: prNumber,
                        stats: PhaseStats(
                            artifactsProduced: report.violations.count
                        )
                    )

                    let markdown = report.toMarkdown()
                    continuation.yield(.log(text: "Report generated: \(report.violations.count) violations\n"))

                    let output = ReportPhaseOutput(report: report, markdownContent: markdown)
                    continuation.yield(.completed(output: output))
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(error: error.localizedDescription, logs: ""))
                    continuation.finish()
                }
            }
        }
    }

    public static func parseOutput(config: PRRadarConfig, prNumber: String) throws -> ReportPhaseOutput {
        let report: ReviewReport = try PhaseOutputParser.parsePhaseOutput(
            config: config, prNumber: prNumber, phase: .report, filename: "summary.json"
        )

        let markdown = try PhaseOutputParser.readPhaseTextFile(
            config: config, prNumber: prNumber, phase: .report, filename: "summary.md"
        )

        return ReportPhaseOutput(report: report, markdownContent: markdown)
    }
}
