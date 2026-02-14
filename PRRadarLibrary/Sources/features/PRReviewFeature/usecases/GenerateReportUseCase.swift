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

    private let config: RepositoryConfiguration

    public init(config: RepositoryConfiguration) {
        self.config = config
    }

    public func execute(prNumber: String, minScore: String? = nil, commitHash: String? = nil) -> AsyncThrowingStream<PhaseProgress<ReportPhaseOutput>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .report))

            Task {
                do {
                    guard let prNum = Int(prNumber) else {
                        continuation.yield(.failed(error: "Invalid PR number: \(prNumber)", logs: ""))
                        continuation.finish()
                        return
                    }

                    let resolvedCommit = commitHash ?? SyncPRUseCase.resolveCommitHash(config: config, prNumber: prNumber)
                    let scoreThreshold = Int(minScore ?? "5") ?? 5

                    continuation.yield(.log(text: "Generating report (min score: \(scoreThreshold))...\n"))

                    let evalsDir = DataPathsService.phaseDirectory(
                        outputDir: config.absoluteOutputDir, prNumber: prNumber, phase: .analyze, commitHash: resolvedCommit
                    )
                    let tasksDir = DataPathsService.phaseSubdirectory(
                        outputDir: config.absoluteOutputDir, prNumber: prNumber, phase: .prepare,
                        subdirectory: DataPathsService.prepareTasksSubdir, commitHash: resolvedCommit
                    )
                    let focusAreasDir = DataPathsService.phaseSubdirectory(
                        outputDir: config.absoluteOutputDir, prNumber: prNumber, phase: .prepare,
                        subdirectory: DataPathsService.prepareFocusAreasSubdir, commitHash: resolvedCommit
                    )

                    let reportService = ReportGeneratorService()
                    let report = try reportService.generateReport(
                        prNumber: prNum,
                        minScore: scoreThreshold,
                        evalsDir: evalsDir,
                        tasksDir: tasksDir,
                        focusAreasDir: focusAreasDir
                    )

                    let reportDir = DataPathsService.phaseDirectory(
                        outputDir: config.absoluteOutputDir, prNumber: prNumber, phase: .report, commitHash: resolvedCommit
                    )
                    let (_, _) = try reportService.saveReport(report: report, reportDir: reportDir)

                    // Write phase_result.json
                    try PhaseResultWriter.writeSuccess(
                        phase: .report,
                        outputDir: config.absoluteOutputDir,
                        prNumber: prNumber,
                        commitHash: resolvedCommit,
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

    public static func parseOutput(config: RepositoryConfiguration, prNumber: String, commitHash: String? = nil) throws -> ReportPhaseOutput {
        let resolvedCommit = commitHash ?? SyncPRUseCase.resolveCommitHash(config: config, prNumber: prNumber)

        let report: ReviewReport = try PhaseOutputParser.parsePhaseOutput(
            config: config, prNumber: prNumber, phase: .report, filename: DataPathsService.summaryJSONFilename, commitHash: resolvedCommit
        )

        let markdown = try PhaseOutputParser.readPhaseTextFile(
            config: config, prNumber: prNumber, phase: .report, filename: DataPathsService.summaryMarkdownFilename, commitHash: resolvedCommit
        )

        return ReportPhaseOutput(report: report, markdownContent: markdown)
    }
}
